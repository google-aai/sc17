#
# Copyright 2017 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

"""Splits image set into multiple directories using thresholds on randnum.

The user provides a source directory, an destination directory, and a set of
sub-directory names and fractions to use for splitting the image set.
The pipeline will copy images from the source directory to one of the
destination sub-directories by thresholding on the randnum field in step 2b.
"""

import argparse
import logging

import apache_beam as beam
from apache_beam.io.filebasedsource import FileBasedSource
from apache_beam.io.filesystems import FileSystems
from apache_beam.options.pipeline_options import PipelineOptions, SetupOptions

import numpy as np

# Keys in dictionaries passed through pipeline
RAND_KEY = 'randnum'
FILENAME_KEY = 'filename'
IMAGE_KEY = 'img'


def run_pipeline(pipeline_args, known_args):
  """Splits images into separate directories using thresholds on randnum.

  Args:
    pipeline_args: arguments ingested by beam pipeline
    known_args: additional arguments for this project, such as the storage
                bucket, source_image_dir, and dest_image_dir.

  Returns:
    [nothing] - runs beam pipeline and copies output files to different dirs
  """
  # Specify pipeline options
  pipeline_options = PipelineOptions(pipeline_args)
  pipeline_options.view_as(SetupOptions).save_main_session = True

  # Attach bucket prefix if running on cloud
  source_images_pattern = known_args.source_image_dir + '/*'
  dest_prefix = known_args.dest_image_dir + '/'
  if known_args.cloud:
    source_images_pattern = ('gs://' + known_args.storage_bucket +
                             '/' + source_images_pattern)
    dest_prefix = ('gs://' + known_args.storage_bucket +
                   '/' + dest_prefix)

  # Get output directories for split images
  split_names = known_args.split_names
  split_fractions = known_args.split_fractions
  dest_images_dirs = [dest_prefix + x + '/' for x in split_names]

  # Create output directories if they do not already exist (for local runs)
  for dest_images_dir in dest_images_dirs:
    if not FileSystems.exists(dest_images_dir):
      FileSystems.mkdirs(dest_images_dir)

  # Log information on source, destination, and split fractions
  split_log_list = [x[0] + '(' + str(x[1]) + ')' for x in
                    zip(split_names, split_fractions)]
  logging.info('Starting ' + ' | '.join(split_log_list) +
               ' split from images with source file pattern ' +
               source_images_pattern)
  logging.info('Destination parent directory: ' + dest_prefix)

  with beam.Pipeline(options=pipeline_options) as p:
    # Read files and partition pipelines
    split_pipelines = (
        p
        | 'read_images'
        >> beam.io.Read(LabeledImageFileReader(source_images_pattern))
        | 'split_images'
        >> beam.Partition(
            generate_split_fn(split_fractions),
            len(split_fractions)
        )
    )

    # Write each pipeline to a corresponding output directory
    for partition, split_name_and_dest_dir in enumerate(
        zip(split_names, dest_images_dirs)):
      _ = (split_pipelines[partition]
           | 'write_' + split_name_and_dest_dir[0]
           >> beam.Map(write_to_directory,
                       dst_dir=split_name_and_dest_dir[1]))

  logging.info('Done splitting image sets')


def generate_split_fn(split_fractions):
  """Generate a partition function using the RAND_KEY field and split fractions.

  The function takes the cumulative sum of a split_fractions list and returns
  a function mapping each bin to a unique integer between 0 and the length of
  the split_fractions list.

  Args:
    split_fractions: data split fractions organized in a list of floats

  Returns:
    returns a function used to split a pipeline into 3 partitions
  """

  cumulative_split_fractions = np.cumsum(split_fractions)

  def _split_fn(data, num_partitions):
    for i, thresh in enumerate(cumulative_split_fractions):
      if data[RAND_KEY] < thresh:
        return i
  return _split_fn


class LabeledImageFileReader(FileBasedSource):
  """A FileBasedSource that yields the entire file content with some metadata.

  A pipeline file source always has a function read_records() that iterates
  through entries within the file. Since each of our files is an image file,
  we don't have multiple entries, so the implementation here is just to read
  the entire file (using f.read()), and return the filename and the random key
  along with it.

  Note that the "if not img: break" clause is there to indicate that after a
  single read, the iterator "blocks" and no longer returns anything. The
  pipeline will then move on to other files.
  """

  def read_records(self, filename, offset_range_tracker):
    """Creates a generator that returns data needed for splitting the images.

    Args:
      filename: full path of the file
      offset_range_tracker: tracks where the last read left off, not important.

    Yields:
      The entire file content along with the filename and RAND_KEY for
      splitting
    """
    with self.open_file(filename) as f:
      while True:
        img = f.read()
        if not img:
          break
        # Change the RAND_KEY denominator's power to match the number of decimal
        # places for randnum in step 2
        yield {
            FILENAME_KEY: filename,
            RAND_KEY: float(filename.split('_')[-2]) / 1e3,
            IMAGE_KEY: img
        }


def write_to_directory(img_and_metadata, dst_dir):
  """Write the serialized image data (png) to dst_dir/filename.

  Filename is the original filename of the image.

  Args:
    img_and_metadata: filename, randnum, and serialized image data (png)
    dst_dir: output directory

  Returns:
    [nothing] - this component serves as a sink
  """
  source = img_and_metadata[FILENAME_KEY]
  with FileSystems.create(dst_dir + FileSystems.split(source)[1]) as f:
    f.write(img_and_metadata[IMAGE_KEY])


def run(argv=None):
  """Main entry point for step 3.

  Args:
    argv: Command line args. See the run_step_3_split_images.sh script for
    typical flag usage.
  """
  parser = argparse.ArgumentParser()
  parser.add_argument(
      '--storage-bucket',
      required=True,
      help='Google storage bucket used to store processed image outputs'
  )
  parser.add_argument(
      '--source-image-dir',
      help='determines where to read original images',
      type=str,
      default='catimages/all_images'
  )
  parser.add_argument(
      '--dest-image-dir',
      help='determines base output directory for splitting images',
      type=str,
      default='catimages'
  )
  parser.add_argument(
      '--split-names',
      help='Names of subsets (directories) split from source image set',
      nargs='+',
      default=['training_images', 'validation_images', 'test_images']
  )
  parser.add_argument(
      '--split-fractions',
      help='Fraction of data to split into subsets',
      type=float,
      nargs='+',
      default=[0.5, 0.3, 0.2]
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