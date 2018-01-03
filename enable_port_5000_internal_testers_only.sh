#!/usr/bin/env bash
# This is for google employees who are using GCP and experience GCE-enforcer
# removing firewall rules that allow jupyter to run on port 5000.
# Run this script in the cloud shell (">_") if you notice that
# you can no longer connect to your notebook on your compute engine VM.
PORT=5000

gcloud compute firewall-rules create allow-jupyter \
  --allow=tcp:$PORT \
  --description="allow jupyter on port 5000 for data science"