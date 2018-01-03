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
#
# Setup.py is called to install packages needed by cloud dataflow VMs.
#
# Some opencv c++ dependencies are needed in addition to python libraries.
#

from subprocess import STDOUT, check_call, CalledProcessError
from sys import platform
import setuptools

NAME = 'dataflow_setup'
VERSION = '1.0'
CV = 'opencv-python==3.3.0.10'
CV_CONTRIB = 'opencv-contrib-python==3.3.0.10'

if __name__ == '__main__':
  if platform == "linux" or platform == "linux2":
    try:
      check_call(['apt-get', 'update'],
                 stderr=STDOUT)
      check_call(['apt-get', '-y', 'upgrade'],
                 stderr=STDOUT)
      # Install opencv-related libraries on workers
      check_call(['apt-get', 'install', '-y', 'libgtk2.0-dev', 'libsm6',
                  'libxrender1', 'libfontconfig1', 'libxext6'],
                 stderr=STDOUT)
    except CalledProcessError:
      pass
  setuptools.setup(name=NAME,
                   version=VERSION,
                   packages=setuptools.find_packages(),
                   install_requires=[CV,
                                     CV_CONTRIB])
