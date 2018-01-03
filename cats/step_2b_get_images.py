#!/usr/bin/python
#
# Copyright 2017 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Runs a beam pipeline to resize and pad images from urls and save to storage.

The images are read from the urls in the source bigquery table.

The images are then filtered by removing any 'None' object returned from a bad
URL, or a 'missing' image provided by Flickr when an image is missing.

The remaining images are resized and padded using the opencv library such that
they are square images of a particular number of pixels (default: 128).

Finally, the images are written into a user provided output directory on Cloud
Storage. The output filenames will look like:

[index]_[randnum_times_1000]_[label].png,

where:

-index is an integer corresponding to the row index of the bigquery table,
prepended with 0's until it is at least 6 digits long,

-randnum_times_1000 is the randnum field from the step 2a query multiplied
by 1000 and truncated at the decimal point, i.e. an integer between 0 and 999.
This was done to make filenames more succinct and avoid extra periods where
there need not be.

-label is either 0 (not cat) or 1 (cat)
"""

import argparse
import logging
import urllib

import apache_beam as beam
from apache_beam.io.filesystems import FileSystems
from apache_beam.io.gcp import bigquery
from apache_beam.options.pipeline_options import PipelineOptions, SetupOptions

import cv2
import numpy as np

# Keys in dictionaries passed through pipeline
RAND_KEY = 'randnum'
IMAGE_KEY = 'img'
INDEX_KEY = 'index'
LABEL_KEY = 'label'

# Bad flickr image: If the image is missing, there are specific dimensions to
# the returned "missing image" from flickr with these dimensions. Furthermore,
# the returned image has exactly a certain number of unique pixel values.
# We will omit images of these exact dimensions and unique values.
BAD_DIMENSIONS = [(374, 500, 3), (768, 1024, 3)]
BAD_UNIQUE_PIXEL_VALUES = 86


def run_pipeline(pipeline_args, known_args):
  """A beam pipeline to resize and pad images from urls and save to storage.

  Args:
    pipeline_args: Arguments consumed by the beam pipeline
    known_args: Extra args used to set various fields such as the dataset and
                table from which to read cat urls and labels, and the bucket
                and image directory to write processed images

  Returns:
    [nothing], just writes processed images to the image directory
  """

  # Specify pipeline options
  pipeline_options = PipelineOptions(pipeline_args)
  pipeline_options.view_as(SetupOptions).save_main_session = True

  # Determine bigquery source from dataset and table arguments
  query = ('SELECT ROW_NUMBER() OVER() as index, original_url, label, randnum'
           ' from [' + known_args.dataset + '.' + known_args.table + ']')
  bq_source = bigquery.BigQuerySource(query=query)

  logging.info('Starting image collection into directory '
               + known_args.output_dir)

  # Create destination directory if it doesn't exist
  output_dir = known_args.output_dir
  if known_args.cloud:
    output_dir = 'gs://' + known_args.storage_bucket + '/' + output_dir

  # Directory needs to be explicitly made on some filesystems.
  if not FileSystems.exists(output_dir):
    FileSystems.mkdirs(output_dir)

  # Run pipeline
  with beam.Pipeline(options=pipeline_options) as p:
    _ = (p
         | 'read_rows_from_cat_info_table'
         >> beam.io.Read(bq_source)
         | 'fetch_images_from_urls'
         >> beam.Map(fetch_image_from_url)
         | 'filter_bad_or_absent_images'
         >> beam.Filter(filter_bad_or_missing_image)
         | 'resize_and_pad_images'
         >> beam.Map(resize_and_pad,
                     output_image_dim=known_args.output_image_dim)
         | 'write_images_to_storage'
         >> beam.Map(write_processed_image,
                     output_dir=output_dir)
         )

  logging.info('Done collecting images')


def fetch_image_from_url(row):
  """Replaces image url field with actual image from the url.

  The images are downloaded and decoded into 3 color bitmaps using opencv.
  All other entries are simply forwarded (index, label, randnum).

  Catches exceptions where the url is bad, the image is not found,
  or the default flickr "missing" image is returned, and returns `None`.
  This is used at the next step downstream (beam.filter) to remove bad images.

  Args:
    row: a dictionary with entries 'index', 'randnum', 'label', 'original_url'

  Returns:
    a dictionary with entries 'index', 'randnum', 'label', 'img'

  """
  url = row['original_url']
  try:
    resp = urllib.urlopen(url)
    img = np.asarray(bytearray(resp.read()), dtype='uint8')
    img = cv2.imdecode(img, cv2.IMREAD_COLOR)

    # Check whether the url was bad
    if img is None:
      logging.warn('Image ' + url + ' not found. Skipping.')
      return None

    return {
        INDEX_KEY: row[INDEX_KEY],
        IMAGE_KEY: img,
        LABEL_KEY: row[LABEL_KEY],
        RAND_KEY: row[RAND_KEY]
    }
  except IOError:
    logging.warn('Trouble reading image from ' + url + '. Skipping.')


def filter_bad_or_missing_image(img_and_metadata):
  """Filter rows where images are either missing (`None`), or an error image.

  An error image from Flickr matches specific dimensions and unique pixel
  values. The likelihood of another image meeting the exact criteria is
  very small.

  Args:
    img_and_metadata: a dictionary/row, or `None`

  Returns:
    True if the row contains valid image data, False otherwise
  """

  if img_and_metadata is not None:
    img = img_and_metadata[IMAGE_KEY]

    # Check whether the image is the "missing" flickr image:
    if img.shape in BAD_DIMENSIONS:
      if len(np.unique(img)) == BAD_UNIQUE_PIXEL_VALUES:
        logging.warn('Image number' + str(img_and_metadata[INDEX_KEY]) +
                     ' has dimensions ' + str(img.shape) +
                     ' and ' + str(BAD_UNIQUE_PIXEL_VALUES) +
                     ' unique pixels.' +
                     ' Very likely to be a missing image on flickr.')
        return False
    return True

  return False


def resize_and_pad(img_and_metadata, output_image_dim=128):
  """Resize the image to make it IMAGE_DIM x IMAGE_DIM pixels in size.

  If an image is not square, it will pad the top/bottom or left/right
  with black pixels to ensure the image is square.

  Args:
    img_and_metadata: row containing a dictionary of the input image along with
                      its index, label, and randnum

  Returns:
    dictionary with same values as input dictionary,
      but with image resized and padded
  """

  img = img_and_metadata[IMAGE_KEY]
  h, w = img.shape[:2]

  # interpolation method
  if h > output_image_dim or w > output_image_dim:
    # use preferred interpolation method for shrinking image
    interp = cv2.INTER_AREA
  else:
    # use preferred interpolation method for stretching image
    interp = cv2.INTER_CUBIC

  # aspect ratio of image
  aspect = float(w) / h

  # compute scaling and pad sizing
  if aspect > 1:  # Image is "wide". Add black pixels on top and bottom.
    new_w = output_image_dim
    new_h = np.round(new_w / aspect)
    pad_vert = (output_image_dim - new_h) / 2
    pad_top, pad_bot = int(np.floor(pad_vert)), int(np.ceil(pad_vert))
    pad_left, pad_right = 0, 0
  elif aspect < 1:  # Image is "tall". Add black pixels on left and right.
    new_h = output_image_dim
    new_w = np.round(new_h * aspect)
    pad_horz = (output_image_dim - new_w) / 2
    pad_left, pad_right = int(np.floor(pad_horz)), int(np.ceil(pad_horz))
    pad_top, pad_bot = 0, 0
  else:  # square image
    new_h = output_image_dim
    new_w = output_image_dim
    pad_left, pad_right, pad_top, pad_bot = 0, 0, 0, 0

  # scale to IMAGE_DIM x IMAGE_DIM and pad with zeros (black pixels)
  scaled_img = cv2.resize(img, (int(new_w), int(new_h)), interpolation=interp)
  scaled_img = cv2.copyMakeBorder(scaled_img,
                                  pad_top, pad_bot, pad_left, pad_right,
                                  borderType=cv2.BORDER_CONSTANT, value=0)

  return {
      INDEX_KEY: img_and_metadata[INDEX_KEY],
      IMAGE_KEY: scaled_img,
      LABEL_KEY: img_and_metadata[LABEL_KEY],
      RAND_KEY: img_and_metadata[RAND_KEY]
  }


def write_processed_image(img_and_metadata, output_dir):
  """Encode the image as a png and write to google storage.

  Creates a function that will read processed images and save them to png
  files in directory output_dir.

  The output image filename is given by a unique index + '_' + randnum to
  the 3rd decimal place + '_' + label + '.png'. The index is also prefix-filled
  with zeros such that the index is at least length 6. This allows us to
  maintain consistent numeric and lexigraphical orderings of filenames by
  the index field up to 1 million images.

  Args:
    img_and_metadata: image, index, randnum, and label
    output_dir: output image directory
    cloud: whether to run/save images on cloud.

  Returns:
    [nothing] - just writes to file destination
  """

  # Construct image filename
  img_filename = (str(img_and_metadata[INDEX_KEY]).zfill(6) +
                  '_' +
                  '{0:.3f}'.format(img_and_metadata[RAND_KEY]).split('.')[1] +
                  '_' + str(img_and_metadata[LABEL_KEY]) +
                  '.png')

  # Encode image to png
  png_image = cv2.imencode('.png', img_and_metadata[IMAGE_KEY])[1].tostring()

  # Use beam.io.filesystems package to create local or gs file, and write image
  with FileSystems.create(output_dir + '/' + img_filename) as f:
    f.write(png_image)


def run(argv=None):
  """Main entry point to for step 2.

  Args:
    argv: Command line arguments. See `run_step_2_get_images.sh` for typical
    usage.
  """
  parser = argparse.ArgumentParser()
  parser.add_argument(
      '--storage-bucket',
      required=True,
      help='Google storage bucket used to store processed image outputs'
  )
  parser.add_argument(
      '--dataset',
      required=True,
      help='dataset of the table through which you will read image urls and'
           ' labels'
  )
  parser.add_argument(
      '--table',
      required=True,
      help='table through which you will read image urls and labels'
  )
  parser.add_argument(
      '--output-dir',
      help='determines where to store processed image results',
      type=str,
      default='cat_images'
  )
  parser.add_argument(
      '--output-image-dim',
      help='The number of pixels per side of the output image (square image)',
      type=int,
      default=128
  )
  parser.add_argument(
      '--cloud',
      dest='cloud',
      action='store_true',
      help='Run on the cloud. If this flag is absent, '
           'it will write processed images to your local directory instead.'
  )

  known_args, pipeline_args = parser.parse_known_args(argv)
  run_pipeline(pipeline_args, known_args)


if __name__ == '__main__':
  logging.getLogger().setLevel(logging.INFO)
  run()