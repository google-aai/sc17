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

"""Cleans up a notebook's metadata and outputs: for use from contributors.

If you would like to contribute or modify notebooks, please run this script
to ensure that all notebooks in the project have cell outputs erased, and any
metadata from other notebook editors (e.g. colab) are removed.

Run this script as follows:

python cleanup_notebooks.py [project-base-directory]

If already in the base directory, run:

python cleanup_notebooks.py .
"""

import json
import os
from glob import glob

# Remove all but valid metadata keys listed here:
# https://ipython.org/ipython-doc/3/notebook/nbformat.html#metadata
VALID_CELL_METADATA_KEYS = ['collapsed', 'autoscroll', 'deletable',
                      'format', 'name', 'tags']
VALID_METADATA_KEYS = ['kernelspec', 'signature']
EXECUTION_COUNT_KEY = 'execution_count'

# Get the script's current directory (project base directory)
base_dir = os.path.dirname(os.path.realpath(__file__))

# Recursively find all notebooks
notebook_paths = [pattern for path in os.walk(base_dir)
                  for pattern in glob(os.path.join(path[0], '*.ipynb'))]
notebook_paths = [x for x in notebook_paths if '.ipynb_checkpoints' not in x]
# Print notebooks to be touched
print(notebook_paths)

# Pull JSON from each notebook
for notebook_path in notebook_paths:
  with open(notebook_path) as notebook_file:
    notebook_json = json.load(notebook_file)

    # Remove keys from cells
    cell_array = notebook_json['cells']
    for cell in cell_array:
      cell_metadata = cell['metadata']
      for key in cell_metadata.keys():
        if key not in VALID_CELL_METADATA_KEYS:
          cell_metadata.pop(key)

      # Reset execution counts for all code cells to 0
      if cell['cell_type'] == 'code':
        cell[EXECUTION_COUNT_KEY] = 0
      elif EXECUTION_COUNT_KEY in cell:
        cell.pop(EXECUTION_COUNT_KEY)

      # Empty outputs for all cells
      if 'outputs' in cell:
        cell['outputs'] = []

    #Remove keys from metadata
    metadata = notebook_json['metadata']
    for key in metadata.keys():
      if key not in VALID_METADATA_KEYS:
        metadata.pop(key)

  clean_string = json.dumps(notebook_json, indent=1, sort_keys=True)
  clean_string = ''.join(line.rstrip() + '\n'
                         for line in clean_string.splitlines())

  with open(notebook_path, 'w') as notebook_file:
    notebook_file.write(clean_string)
