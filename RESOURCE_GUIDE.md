# Resource Guide

This guide is meant to provide some resource, time, and money tradeoffs such
that you can choose the best configuration for your data science experience!

## STOPPING VM INSTANCES

**Make sure to stop your VM instance when you are not using it!**

When you start a VM, GCP will charge you an hourly rate (see below). If you are
not actively running tasks on the VM or using the interface, you should stop the
instance to save money. To do so, you can either do it through the
[web ui](https://console.cloud.google.com/compute/instances) by clicking on the
vertical dots at the right of your instance and stopping it, or use the command
line from cloud shell:

```
gcloud compute instances stop [vm-instance-name]
```

## GPU or No GPU

The NVIDIA Tesla K80 is significantly cheaper than the Tesla P100, but not
nearly as powerful. The P100 can speed up deep network training by 10-20x
compared to no GPU. If you plan to spend a lot of time visualizing and debugging
data and less time running massive training jobs, it may be a good idea to start
without a GPU. When you reach a step in the tutorial where you are training and
optimizing deep neural nets is required, a GPU can saves you a lot of time,
and potentially money. To compare costs and performance, consider the
[training task](cats/step_8_to_9.ipynb) used in the `cats`
project:

* **No GPU:** A 2 CPU VM costs around $0.10 per hour when active. Training on
the full dataset in a notebook (which only runs on 1 CPU) takes about 8 hours.
* **K80**: around $0.55 per hour when active. Training takes about 31 minutes.
* **P100**: around $1.50 per hour when active. Training takes about 25 minutes.

(It is possible that the default configuration does not optimize for P100, and
further savings can be achieved.)

## Dataflow CPUs

By default, our project is tuned to run tasks that will not incur more than a
few dollars to your account, while ensuring that jobs complete quickly.
If you would like to save money at the cost of extra time, dataflow jobs can be
tuned using flags such as `--num_workers` and `--worker_machine_type`. The:
example below dispatches a job on 20 machines with a worker type that contains
4 cpus per machine:

```
--num_workers 20 \
--worker_machine_type n1-standard-4 \
```

If you are running a lightweight task, such as a small sample of cat images,
consider using fewer machines and/or changing the worker machine type to a
simpler worker. This can reduce resources required to boot up and setup
machines, and reduce communication overhead between machines.