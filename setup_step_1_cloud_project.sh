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
# Set up network, compute engine VM, storage, and dataset for the sc17 project.
#
# To ensure correct setup, run this script in the default cloud shell
# in the GCP web console (the ">_" icon at the top right).

err() {
  echo "ERROR [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
  exit 1
}

# Check argument length
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 project-name [gpu-type] [compute-region] [dataflow-region]"
  echo "  project-name is the project name you specified during setup"
  echo "  gpu-type: either K80, P100, or None"
  echo "    (default: None)"
  echo "  compute-region: where you will be running data science notebooks"
  echo "    (default: us-east1)"
  echo "  dataflow-region: where you will run dataflow preprocessing jobs"
  echo "    (default: us-central1)"
  exit 1
fi

PROJECT=$1

# Parse optional arguments
if [ "$#" -ge 3 ]; then
  COMPUTE_REGION=$3
else
  COMPUTE_REGION=us-east1
fi

if [ "$#" -ge 4 ]; then
  DATAFLOW_REGION=$4
else
  DATAFLOW_REGION=us-central1
fi

if [ "$#" -ge 2 ]; then
  GPU_TYPE=$2
else
  GPU_TYPE=None
fi

#### Check quotas ####

#######################################
# Check quota and throw error if quota value is below the lower bound.
#
# The purpose of enforcing these quota bounds is to ensure a good user
# experience, since without quota increases some jobs and notebooks may take
# very long to run.
#
# Globals:
#   None
# Arguments:
#   quota_json: the quota json to parse
#   metric_name: the quota metric name
#   lower_bound: lower bound on the quota value
# Returns:
#   None
#######################################
check_quota() {
  METRIC=$(echo "$1" \
    | jq ".quotas | map(select(.metric ==\"$2\")) | .[0].limit")
  if [ "$METRIC" -lt $3 ]; then
    err "Quota $2 must be at least $3: value = $METRIC. Please increase quota!"
  fi
}

GLOBAL_QUOTA=$(gcloud --format json compute project-info \
  describe --project $PROJECT)
DATAFLOW_REGION_QUOTA=$(gcloud --format json compute regions \
  describe $DATAFLOW_REGION)

# The quota requirements here may be lower than the recommended in the README,
# but this is mainly to ensure a minimum level of performance.

echo "Checking quotas for $DATAFLOW_REGION..."
check_quota "$DATAFLOW_REGION_QUOTA" IN_USE_ADDRESSES 50
check_quota "$DATAFLOW_REGION_QUOTA" DISKS_TOTAL_GB 65536
check_quota "$DATAFLOW_REGION_QUOTA" CPUS 200

echo "Checking global quotas..."
check_quota "$GLOBAL_QUOTA" CPUS_ALL_REGIONS 200

# If a gpu type is requested, check that you have at least one available
# in the requested region.
if [ "$GPU_TYPE" != "None" ]; then
  echo "Checking quotas for $COMPUTE_REGION..."
  # Get cloud compute info for your region
  COMPUTE_INFO=$(gcloud compute regions describe $COMPUTE_REGION) || exit 1
  # Verify that you have gpus available to create a VM
  GPUS_QUOTA=$(echo "$COMPUTE_INFO" \
    | grep -B1 "metric: NVIDIA_${GPU_TYPE}" \
    | grep limit \
    | cut -d' ' -f3 \
    | cut -d'.' -f1)
  # Get gpus in use by parsing the output
  GPUS_IN_USE=$(echo "$COMPUTE_INFO" \
    | grep -A1 "metric: NVIDIA_${GPU_TYPE}" \
    | grep usage \
    | cut -d' ' -f4 \
    | cut -d'.' -f1)

  # Verify that you still have gpus available
  if [ "$GPUS_QUOTA" -gt "$GPUS_IN_USE" ]; then
    echo "GPUs are available for creating a new VM!"
  else
    err "Not enough GPUs available! Either increase quota or stop existing VMs
     with GPUs. Quota: $GPUS_QUOTA, Avail: $GPUS_IN_USE"
  fi
fi

# Get a default zone for the vm based on region and GPU availabilities
# See https://cloud.google.com/compute/docs/gpus/#introduction.
if [ "$GPU_TYPE" == "K80" ]; then
  ACCELERATOR_ARG="--accelerator type=nvidia-tesla-k80,count=1"

  case "$COMPUTE_REGION" in
    "us-east1")
      ZONE="us-east1-d"
      ;;
    "us-west1")
      ZONE="us-west1-b"
      ;;
    "europe-west1")
      ZONE="europe-west1-b"
      ;;
    "asia-east1")
      ZONE="asia-east1-b"
      ;;
    *)
      err "Zone does not contain any gpus of type $GPU_TYPE"
      ;;
  esac
elif [ "$GPU_TYPE" == "P100" ]; then
  ACCELERATOR_ARG="--accelerator type=nvidia-tesla-p100,count=1"

  case "$COMPUTE_REGION" in
    "us-east1")
      ZONE="us-east1-c"
      ;;
    "us-west1")
      ZONE="us-west1-b"
      ;;
    "europe-west1")
      ZONE="europe-west1-d"
      ;;
    "asia-east1")
      ZONE="asia-east1-a"
      ;;
    *)
      err "Zone does not contain any gpus of type $GPU_TYPE"
      ;;
  esac
elif [ "$GPU_TYPE" != "None" ]; then
  err "Unknown GPU type $GPU_TYPE"
else
  ACCELERATOR_ARG=""
  # Assign zone which is the region name + "-a",
  # except regions without such zones
  case "$COMPUTE_REGION" in
    "europe-west1")
      ZONE="europe-west1-b"
      ;;
    "us-east1")
      ZONE="us-east1-b"
      ;;
    *)
      ZONE="$COMPUTE_REGION-a"
      ;;
  esac
fi

echo "All quota requirements passed!"
echo "Using zone $ZONE for data science VM creation"


#### CLOUD PROJECT APIS ####
# Enable google apis if they aren't already enabled
ENABLED_SERVICES=$(gcloud services list --enabled)
check_and_enable_service() {
  SERVICE_ENABLED=$(echo "$ENABLED_SERVICES" | grep $1) || true
  if [[ -z "$SERVICE_ENABLED" ]]; then
    gcloud services enable $1 || err "could not enable service $1"
  fi
}

echo "Checking and Enabling Google APIs..."
check_and_enable_service dataflow.googleapis.com
check_and_enable_service logging.googleapis.com
check_and_enable_service cloudresourcemanager.googleapis.com
echo "APIs enabled!"


#### CREATE VM FOR DATA SCIENCE ####
# Create a VM to use for supercomputing!
# Note that notebooks primarily run on a single cpu core, so we do not need too
# many cores. Tensorflow will be configured to use a gpu, which significantly
# speeds up the running time of deep net training.

if [ "$GPU_TYPE" != "None" ]; then
  STARTUP_SCRIPT='#!/bin/bash
    echo "Checking for CUDA and installing."
    # Check for CUDA and try to install.
    if ! dpkg-query -W cuda-8-0; then
      curl -O http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_8.0.61-1_amd64.deb
      dpkg -i ./cuda-repo-ubuntu1604_8.0.61-1_amd64.deb
      apt-get update
      apt-get install cuda-8-0 -y
    fi'
else
  STARTUP_SCRIPT=""
fi

COMPUTE_INSTANCE=$PROJECT-compute-instance
gcloud compute instances create $COMPUTE_INSTANCE \
  --zone $ZONE \
  --custom-cpu 2 \
  --custom-memory 13 \
  $ACCELERATOR_ARG \
  --image-family ubuntu-1604-lts \
  --image-project ubuntu-os-cloud \
  --boot-disk-type pd-standard \
  --boot-disk-size 256GB \
  --scopes cloud-platform \
  --network default \
  --maintenance-policy TERMINATE \
  --restart-on-failure \
  --metadata startup-script="'$STARTUP_SCRIPT'" \
  || err "Error starting up compute instance"

echo "Compute instance created successfully! GPU=$GPU_TYPE"

#### SETUP VM ENVIRONMENT FOR DATA SCIENCE ####

# Create bashrc modification script
BUCKET=$PROJECT-bucket
echo "
#!/bin/bash
sed -i '/export PROJECT.*/d' ~/.bashrc
echo \"export PROJECT=$PROJECT\" >> ~/.bashrc
echo \"Added PROJECT=$PROJECT to .bashrc\"
sed -i '/export BUCKET.*/d' ~/.bashrc
echo \"export BUCKET=$BUCKET\" >> ~/.bashrc
echo \"Added BUCKET=$BUCKET to .bashrc\"
sed -i '/export DATAFLOW_REGION.*/d' ~/.bashrc
echo \"export DATAFLOW_REGION=$DATAFLOW_REGION\" >> ~/.bashrc
echo \"Added the following lines to .bashrc\"
tail -n 3 ~/.bashrc
" > env_vars.sh

retry=0
# Retry SSH-ing 5 times
until [ $retry -ge 5 ]
do
  echo "SSH retries: $retry"

  # Create a temporary firewall rule for ssh connections
  # Ignore error if rule is already created.
  gcloud compute firewall-rules create allow-ssh \
    --allow tcp:22 \
    --source-ranges 0.0.0.0/0 \
    || true

  # SSH and execute script
  gcloud compute config-ssh
  gcloud compute ssh --zone $ZONE $COMPUTE_INSTANCE -- 'bash -s' < ~/env_vars.sh \
    && break
  retry=$[$retry + 1]

  echo "SSH connection failed. Machine may still be booting up. Retrying in 30 seconds..."
  sleep 30
done

if [ $retry -ge 5 ]; then
  err "Unsuccessful setting up bashrc environment for $COMPUTE_INSTANCE"
fi

#### STORAGE ####
# Create a storage bucket for the demo if it doesn't exist.
echo "Creating a storage bucket and dataset..."
gsutil mb -p $PROJECT -c regional -l $COMPUTE_REGION gs://$PROJECT-bucket/ \
  || true

# Create a new dataset for storing tables in this project if it doesn't exist
# If this is your first time making a dataset, you may be prompted to select
# a default project.
bq mk dataset || true
echo "Done!"
