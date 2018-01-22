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
# Set up a VM environment for data science with Tensorflow GPU support.
#
# Note: RUN THIS ON A COMPUTE ENGINE VM, not in the cloud shell!
#

#### Exit helper function ####
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
  exit 1
}

#### Bash variables ####
# The directory of the shell script, e.g. ~/code in the lecture slides.
BASE_DIR=$(dirname "$0")
# The remote port for Jupyter traffic.
PORT=5000
# Check if machine has GPU support.
LSPCI_OUTPUT=$(lspci -vnn | grep NVIDIA)

#### APT-GET library installations ####

# Update apt-get
sudo apt-get update -y

# Install python and pip libraries
sudo apt-get install -y \
  python-pip \
  python-dev \
  build-essential \
  || err 'failed to install python/pip libraries'

# Install opencv c++ library dependencies
sudo apt-get install -y \
  libsm6 \
  libxrender1 \
  libfontconfig1 \
  libxext6 \
  || err 'failed to install opencv dependencies'

# If we are using a GPU machine, install cuda libraries
if [ -n "$LSPCI_OUTPUT" ]; then
  # The 16.04 installer works with 16.10.
  sudo curl -O http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_8.0.61-1_amd64.deb \
    || err 'failed to find cuda repo for ubuntu 16.0'
  sudo dpkg -i ./cuda-repo-ubuntu1604_8.0.61-1_amd64.deb
  sudo apt-get update
  sudo apt-get install cuda-8-0 -y \
    || err 'failed to install cuda 8.0'

  # Check for available cuda 8.0 libraries
  CUDA_LIBRARIES_URL=http://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu1404/x86_64/

  CUDA_8_LIBRARIES=$(curl $CUDA_LIBRARIES_URL \
    | grep libcudnn6 \
    | grep amd64.deb \
    | grep cuda8.0 \
    | sed "s/^.*href='\(.*\)'>.*$/\1/") \
    || err 'failed to find cuda 8 libraries'

  # Get latest runtime and developer libraries for cuda 8.0
  # Download and install
  CUDA_8_RUNTIME_LIBRARY=$(echo "$CUDA_8_LIBRARIES" | grep -v dev | tail -n 1)
  CUDA_8_DEV_LIBRARY=$(echo "$CUDA_8_LIBRARIES" | grep dev | tail -n 1)

  sudo curl -O $CUDA_LIBRARIES_URL$CUDA_8_RUNTIME_LIBRARY \
    || err 'failed to download cuda runtime library'
  sudo curl -O $CUDA_LIBRARIES_URL$CUDA_8_DEV_LIBRARY \
    || err 'failed to download cuda developer library'
  sudo dpkg -i $CUDA_8_RUNTIME_LIBRARY \
    || err 'failed to install cuda runtime libraries'
  sudo dpkg -i $CUDA_8_DEV_LIBRARY \
    || err 'failed to install cuda developer libraries'

  # Point TensorFlow at the correct library path
  # Export to .bashrc so env variable is set when entering VM shell
  # Remove existing line in bashrc if it already exists.
  sed -i '/export LD_LIBRARY_PATH.*\/usr\/local\/cuda-8.0/d' $HOME/.bashrc
  echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda-8.0/lib64' \
    >> $HOME/.bashrc

  # Install cuda profiler tools development library
  sudo apt-get install -y libcupti-dev \
    || err 'failed to install cuda profiler tools'
fi


#### Python Virtual Environment Setup ####

# Upgrade pip and virtual env
sudo pip install --upgrade pip
sudo pip install --upgrade virtualenv

# Create a virtual environment.
virtualenv $HOME/env

# Create a function to activate environment in shell script.
activate () {
  . $HOME/env/bin/activate
}
activate || err 'failed to activate virtual env'

# Save activate command to bashrc so logging into the vm immediately starts env
# Remove any other commands in bashrc that is attempting to start a virtualenv
sed -i '/source.*\/bin\/activate/d' $HOME/.bashrc
echo 'source $HOME/env/bin/activate' >> $HOME/.bashrc

# Install requirements.txt
pip install -r $BASE_DIR/requirements.txt \
  || err 'failed to pip install a required library'

# If this is a GPU machine, install tensorflow-gpu
if [ -n "$LSPCI_OUTPUT" ]; then
  pip install tensorflow-gpu==1.3.0
fi

#### JUPYTER SETUP ####

# Switch into $BASE_DIR, e.g. ~/code
cd $BASE_DIR

# Create a config file for jupyter. Defaults to location ~/.jupyter/jupyter_notebook_config.py
jupyter notebook --generate-config

# Append several lines to the config file
echo "c = get_config()" >> ~/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.ip = '*'" >> ~/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.open_browser = False" >> ~/.jupyter/jupyter_notebook_config.py
echo "c.NotebookApp.port = $PORT" >> ~/.jupyter/jupyter_notebook_config.py

# Create a password for jupyter. This is necessary for remote web logins.
# The password will be hashed and written into ~/.jupyter/jupyter_notebook_config.json
jupyter notebook password

# Hacky way to parse the json to pick up the hashed password and add to config file
PASSWORD_HASH=$(cat ~/.jupyter/jupyter_notebook_config.json | grep password | cut -d"\"" -f4)
echo "c.NotebookApp.password = u'$PASSWORD_HASH'" >> ~/.jupyter/jupyter_notebook_config.py
echo "Done with jupyter setup!"

# Add some env variables into your bashrc
echo 'Done with installation! Make sure to type: . ~/.bashrc to finish setup.'

#### DONE ####