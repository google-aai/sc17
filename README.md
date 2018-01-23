# Making Friends with ML Tutorial

Authors: Cassie Kozyrkov (@kozyrkov) and Brian Foo (@bkungfoo)

Team: Google Applied AI

## Create and Setup Cloud Project

**This tutorial is meant to run fully on the Google Cloud Platform.**

Starting with your web browser, do the following:

* Open a browser and sign up for a [google account](https://accounts.google.com).
* Sign into your account.
* [Create a new GCP project](https://cloud.google.com/resource-manager/docs/creating-managing-projects)
and [enable billing](https://cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_a_project).

### Editing Resource Quota

**Why edit resource quota?**  To complete this tutorial, you will need more computing resources than your
Google Cloud Platform account has access to by default.  One reason that accounts start out with limits on
resources is that this protects users from being billed unexpectedly for the more expensive options. 
For more information, see the [quotas documentation page](https://cloud.google.com/compute/quotas).

For this project, we will require several types of resources:

* **Compute Engine VM for Data Science:** We will create a VM that you will log
into and do most of your work and run notebooks. You will have the option of
creating a VM with a GPU choice, or no GPU. A GPU is strongly recommended for
deep network training because it dramatically cuts down the time to completion.
However, the cost is also higher. Please refer to the
[resource guide](RESOURCE_GUIDE.md) for a brief discussion and comparison of
performances and costs.

* **Cloud resources:** We will be using Dataflow to run distributed
preprocessing jobs. Thus, we need to extend quotas on Cloud resources, such as
CPUs, IP addresses, and total disk space.

We will be setting quotas for these two types of resources. Note that quotas
only determine the maximum amount of a resource that your project is allowed to
request! It does not mean that your jobs will use this amount necessarily,
but that you are permitted to use up to this amount. The general
guideline is to set higher quotas such that there is no need to readjust them
for compute-intensive tasks.

<span style="color:darkgreen">**Quota Setup Instructions:**</span>

To set up the data science VM, we will need to extend the quota for GPUs.
* Select your project from the list on the
[resource quota page](https://console.cloud.google.com/iam-admin/quotas).
  * (If this is the first time creating the project, compute engine may still
  need to boot up. If the quota page does not have GPU options, click on
  "Compute Engine" in the dropdown menu on the top left, and click quota there.
  Wait for it to load, and return to the quota page above.)
* If you would like to try out a GPU machine (recommended),
[find a region that has gpu support](https://cloud.google.com/compute/docs/gpus/).
 At the time this tutorial was written, valid regions include
 us-east1, us-west1, europe-west1, and asia-east1.
* Select your chosen region from the Region dropdown menu.
 Then select the following:
  * NVIDIA K80 GPUs
  * NVIDIA P100 GPUs
* Click "+ edit quotas" at the top of the page. Change the fields above to
the following values:
  * NVIDIA K80 GPUs: 1
  * NVIDIA P100 GPUs: 1
* Follow the process to submit a request.

To setup cloud resources for preprocessing jobs, follow a similar request as
above to edit quotas:
* Find a region with
 [Dataflow support](https://cloud.google.com/dataflow/docs/concepts/regional-endpoints#supported_regional_endpoints)
 At the time this tutorial was written, valid regions include us-central1 and
 europe-west1.
* Select this region in the dropdown menu on the
[resource quota page]((https://console.cloud.google.com/iam-admin/quotas)).
* Change the following quotas:
  * CPUs: 400
  * In-use IP addresses: 100
  * Persistent Disk Standard (GB): 65536
* Select region "Global" in the dropdown menu:
  * Change the following quotas:
    * CPUs (all regions): 400

After you have completed these steps, you will need to wait until you receive
an email approving of the quota increases. Please note that you may be asked to
provide credit card details to confirm these increases.

## Setup Cloud Project Components and API

<span style="color:red">*Expected setup time: 5 minutes*</span>

Click on the ">_" icon at the top right of your web console to open a cloud
shell. Inside the cloud shell, execute the following commands:

```
git clone https://github.com/google-aai/sc17.git
cd sc17
```

If you happen to have the project files locally, you can also upload locally by
clicking on the 3 vertically arranged dots on the top right of the shell window,
and then click "upload file".

After you have the proper scripts uploaded, set permissions on the following
script:

```
chmod 777 setup_step_1_cloud_project.sh
```

Then run the script to create storage, dataset,
and compute VMs for your project (Note: using the "sh" command will fail as it
is missing some necessary syntax in the cloud shell environment.)
```
./setup_step_1_cloud_project.sh project-name [gpu-type] [compute-region] [dataflow-region]
```

where:
* [project-name] is the ID of the project you created (check the Cloud Dashboard for the ID extension if needed)
* [gpu-type] (optional) is either None, K80, or P100
(default: None)
* [compute-region] (optional) is the region you will create your data science VM
(default: us-east1)
* [dataflow-region] (optional) is where you will run dataflow preprocessing jobs
(default: us-central1)

If this is your first time setting up the project, you will be prompted during
the course of running the script, such as selecting the number corresponding to
your project. Enter what is needed to allow the script to continue running.

If the script stops with an error message "ERROR [timestamp]: message" (e.g.
quota limits are too low), use relevant parts of the error message to fix your
project setting if needed, and rerun the script.

## Setting up your VM environment

### Library installations

<span style="color:red">*Expected setup time: 15 minutes*</span>

From the
[VM instances page](https://console.cloud.google.com/compute/instances),
click the "SSH" text under "Connect" to connect to your compute VM instance.
You may have to click twice if your browser auto-blocks pop-ups.

In the new window, run git clone to download the project onto your VM, and cd
into it:

```
git clone https://github.com/google-aai/sc17.git
cd sc17
```

If you happen to have the project files locally, you can also upload locally by
opening your Storage Bucket from the GCP Console menu and dragging your local files
over.  Then in your VM window, download them from your storage bucket by running:

```
gsutil cp [gs://[bucket-name]/* .]
```

Note that tab-complete will work after ```gs://``` if you don't know your bucket name.

After you have the script files downloaded to your VM, run the following script:

```
sh setup_step_2_install_software.sh
```

The script should setup opencv dependencies, python, virtual env, and
jupyter. It will also automatically detect the presence of
an NVIDIA GPU and install/link CUDA libraries and tensorflow GPU if necessary.
The script will also prompt you to **provide a password** at some
point. This password is for connecting to jupyter from your web browser.  Please
take note of it since you'll be prompted to enter it when you start working in Jupyter.

To complete and test the setup, reload bashrc to load the newly created virtual
environment:

```
. ~/.bashrc
```

## Use Unix Screen to Start a Notebook

Screen takes a little to get used to, but it will make working on cloud VMs much
more pleasant, especially with a project that needs to run many tasks!

For those not familiar with the unix screen command, Screen is known as a
"terminal multiplexer", which allows you to run multiple terminal (shell)
instances at the same time in your ssh session. Furthermore, Screen sessions are
NOT tied to your ssh session, which means that if you accidentally log out or
disconnect from your ssh session in the middle of running a long process running
on your VM, you will not lose your work!

Furthermore, you might want multiple processes running simultaneously and have
an easy way to switch back and forth. A simple example is that you want to leave
your Jupyter notebook open while running a Cloud Dataflow job (which you do not
want abruptly canceled!). Running these in separate terminals is ideal.

To start screen for the first time, run:

```
screen
```

and press return. This opens up a screen terminal (defaults to terminal 0).

Let's create one more Screen terminal (terminal 1) by pressing `Ctrl-a`, and then
`c` (We will write this shorthand as `Ctrl-a c`)

You can now jump between the two terminals by using `Ctrl-a n`, or access them
directly using `Ctrl-a 0` or `Ctrl-a 1`.

Go to terminal 0 by typing `Ctrl-a 0`, and then type:

```
jupyter notebook
```

to start jupyter.

Finally, detach from both Screen terminals by typing `Ctrl-a d`. If you want to
resume the screen terminals, simply type:

```
screen -R
```

Fantastic! Now let's do another cool trick: Make sure you are detached from
Screen terminals (type `Ctrl-a d` if necessary), and then exit the machine
by typing:

```
exit
```

at the command line. You just exited the machine, but the Screen terminals are
still be running, including Jupyter which you started in Screen!

## Connecting to Jupyter

Jupyter is now running inside a Screen terminal even though your ssh session has
ended. Let's try it out through an ssh tunnel (For security reasons, we will
not simply open up a firewall port and show your notebook to the entire world!)

On your local computer, make sure you have [gcloud sdk installed](https://cloud.google.com/sdk/downloads).
Then run:

```
gcloud init
```

Follow the instructions and choose your project, and then choose the region
corresponding to where your vm was created. After this has been setup, run:

```
gcloud compute config-ssh
```

After this runs successfully, you will get this back in your shell:

```
You should now be able to use ssh/scp with your instances.
For example, try running:

  $ ssh [instance-name].[zone-name].[project-name]
```  
  
Run the suggested command to check that ssh works when connecting to your cloud
VM. Then exit the ssh shell by typing `exit`.

Now we are ready to connect to Jupyter! Run the same ssh command again, but this
time, add some flags and ports:

```
ssh -N -f -L localhost:8888:localhost:5000 [instance-name].[zone-name].[project-name]
```

This command basically configures port forwarding, redirecting port 5000 on your
cloud VM to your own computer's port 8888. Now go to your web browser, and type:

```
localhost:8888
```

If you see a password page for Jupyter, enter your password as prompted.
Once you are in, you can see the notebook view of the directory you
started Jupyter in.

Before proceeding, please read the [resource guide](RESOURCE_GUIDE.md) to beware
of common pitfalls (such as forgetting to stop your VM when not using it!) and
other ways to save on cost.

**Hooray! [Let's go detect some cats!](cats/README.md)**
