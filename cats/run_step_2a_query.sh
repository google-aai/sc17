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
# Run bigquery command to write result of step_2a_query.sql to a table.
#

QUERY=$(cat 'step_2a_query.sql')

bq query --use_legacy_sql=false --destination_table=dataset.catinfo "$QUERY" \
  || exit 1

echo "Successfully wrote query output to table dataset.catinfo!"