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
# This script runs step 2 part B to collect positive and negative image samples!
# Execute run_step_2a_query.sh first to collect cat-not-cat urls!
#
# Reads image urls and labels from $DATASET.$TABLE, resizes and outputs images
# in a Google storage bucket $BUCKET under a directory $IMAGE_DIR/all_images.

if [ "$#" -ne 5 ]; then
    echo "Usage: $0 project-name dataset table bucket-name image-dir"
    echo "dataset.table is the table that stores positive and negative cat labels, urls, and random numbers"
    echo "(bucket-name does not contain prefix gs://)"
    exit 1
fi

PROJECT=$1
DATASET=$2
TABLE=$3
BUCKET=$4
IMAGE_DIR=$5

# This starts a DataflowRunner job on Google Cloud.
# In order to manage read/write permissions and billing for dataflow, the
# job requires a project given by your current project
# which dispatches --num_workers
python -m step_2b_get_images \
  --project $PROJECT \
  --runner DataflowRunner \
  --staging_location gs://$BUCKET/$IMAGE_DIR/staging \
  --temp_location gs://$BUCKET/$IMAGE_DIR/temp \
  --num_workers 50 \
  --worker_machine_type n1-standard-4 \
  --setup_file ./setup.py \
  --region $DATAFLOW_REGION \
  --dataset dataset \
  --table $TABLE \
  --storage-bucket $BUCKET \
  --output-dir $IMAGE_DIR/all_images \
  --output-image-dim 128 \
  --cloud
