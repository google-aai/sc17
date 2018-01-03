#!/bin/bash -eu
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
#
# Note: Run step 2 before running this step!
#
# Takes images in $IMAGE_DIR/all_images and splits them to three separate
# folders: $IMAGE_DIR/training_images, $IMAGE_DIR/validation_images,
# and $IMAGE_DIR/test_images.

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 project-name bucket-name image-dir"
    echo "(bucket-name does not contain prefix gs://)"
    echo "image-dir is the directory in which you ran for step 2,
     should contain an `all_images` folder"
    exit 1
fi

PROJECT=$1
BUCKET=$2
IMAGE_DIR=$3

python -m step_3_split_images \
  --project $PROJECT \
  --runner DataflowRunner \
  --staging_location gs://$BUCKET/$IMAGE_DIR/staging \
  --temp_location gs://$BUCKET/$IMAGE_DIR/temp \
  --num_workers 20 \
  --worker_machine_type n1-standard-4 \
  --setup_file ./setup.py \
  --region $DATAFLOW_REGION \
  --storage-bucket $BUCKET \
  --source-image-dir $IMAGE_DIR/all_images \
  --dest-image-dir $IMAGE_DIR \
  --split-names training_images validation_images test_images \
  --split-fractions 0.5 0.3 0.2 \
  --cloud

