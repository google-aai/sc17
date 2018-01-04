# Feline ML Tutorial

## Verify environment variables

Let's [SSH back into our cloud VM](https://console.cloud.google.com/compute/instances)
by clicking the SSH link. Type:

```
screen -R
```

to resume the screen terminals.

Jupyter should already be running in terminal 0, so let's use terminal 1 to
check up on some things. Type `Ctrl-a 1` to switch to terminal 1.

Let us confirm that bash env variables are set
correctly to make our lives easier. Confirm that the following displays your
project and storage bucket names correctly:

```
echo $PROJECT
echo $BUCKET
echo $DATAFLOW_REGION
```

## Step 0: Introduction and Setup Validation

If you aren't connected to Jupyter via your browser yet,
[connect to it now.](../README.md#connect-to-jupyter) Click on the `cats`
directory to see all of the notebooks we will be using.

Click the `step_0_to_0.ipynb` notebook to get a "Hello World" view of tools that
we will use, and to verify that we have indeed connected tensorflow to our gpu.

Note that the first time you run a notebook, the notebook is by default
*not trusted* over the internet. You will have to click the "Not Trusted" button
on the top right to switch to "Trusted" mode in order to run it.

The last code entry should return a dictionary containing devices you have
available on the machine. There should be a cpu available.
If you chose a GPU for your machine, confirm that the resulting list also
contains an entry like `u'/gpu:0'`.

When you have finished running the notebook, either shutdown the kernel from
the Kernel dropdown menu, or click the notebook from the directory view and
click "shutdown" to free up resources for the next step.

## Step 1: Performance Metrics and Requirements

Work through `step_1_to_3.ipynb`. Steps 2 and 3 are left blank intentionally as
we will be running them using super cool distributed dataflow jobs!

## Step 2: Getting the Data

In your VM shell, switch to screen terminal 1, i.e. `Ctrl-a 1`. Switch to the 
`cats` directory:

```
cd ~/sc17/cats
```

Step 2 consists of two parts listed below.

### Step 2a: Collect Metadata in Bigquery Table

<span style="color:red">*Expected run time: < 1 minute*</span>

To collect our cat images, we will use bigquery on a couple of public tables
containing image urls and labels. The query is contained in the
`step_2a_query.sql` file.

Run the following script to execute the query and write the results into a
bigquery table `$PROJECT.dataset.catinfo`.

```
sh run_step_2a_query.sh
```

### Step 2b: Collect Images into Cloud Storage using Dataflow

<span style="color:red">*Expected run time: 25 minutes*</span>

**For an in-depth discussion of Cloud Dataflow steps 2b and 3, see the
[Dataflow Preprocessing Tutorial](DATAFLOW_TUTORIAL.md).**

Once you have the output table `$PROJECT.dataset.catinfo` populated, run the
following to collect images from their urls are write them into storage:

```
sh run_step_2b_get_images.sh $PROJECT dataset catinfo $BUCKET catimages
```

To view the progress of your job, go to the
[Dataflow Web UI](https://console.cloud.google.com/dataflow)
and click on your job to see a graph. Clicking on each of the components of
the graph will show you how many elements/images have been processed by that
component. The total number of elements should be approximately 80k.

The images will be written into `gs://$BUCKET/catimages/all_images`.

## Step 3: Splitting the Data

<span style="color:red">*Expected run time: 20 minutes*</span>

The next step is to split your dataset into training, validation, and test.
The script we will be using is `run_step3_split_images.sh`. If you inspect
the script, you will notice that the python class takes in general
split fractions and output names as parameters for flexibility, but the script
has been written to provide an example that splits the data into
0.5 (50%) training images, 0.3 (30%) validation images, and 0.2 (20%) testing
images, e.g. with arguments:

```
  --split-names training_images validation_images test_images
  --split-fractions 0.5 0.3 0.2 \
```

Run the script as is (do not change it for the time being!):

```
sh run_step_3_split_images.sh $PROJECT $BUCKET catimages
```

## Step 4: Exploring the Training Set

<span style="color:red">*Expected image set download time: < 2 minutes*</span>

Let's download a subset of the training images to the VM from storage. We will
use wildcards to choose about 2k images for training, and 1k images for
debugging.

In screen terminal 1 (Go to the VM shell and type `Ctrl+a 1`), create a folder
to store your training and debugging images, and then copy a small sample of
training images from cloud storage:

```
mkdir -p ~/data/training_small
gsutil -m cp gs://$BUCKET/catimages/training_images/000*.png ~/data/training_small/
gsutil -m cp gs://$BUCKET/catimages/training_images/001*.png ~/data/training_small/
mkdir -p ~/data/debugging_small
gsutil -m cp gs://$BUCKET/catimages/training_images/002*.png ~/data/debugging_small
echo "done!"
```

Once this is done, you can begin work on notebooks `step_4_to_4_part1.ipynb` and
`step_4_to_4_part2.ipynb`.  We suggest running the lines below before you begin with
the notebooks so the downloads can happen while you are working with Jupyter and you
needn't wait idly.

<span style="color:red">*Expected image set download time: 20 minutes*</span>

Download all of your image sets to the VM. Then set aside a few thousand
training images for debugging.

```
mkdir -p ~/data/training_images
gsutil -m cp gs://$BUCKET/catimages/training_images/*.png ~/data/training_images/
mkdir -p ~/data/validation_images
gsutil -m cp gs://$BUCKET/catimages/validation_images/*.png ~/data/validation_images/
mkdir -p ~/data/test_images
gsutil -m cp gs://$BUCKET/catimages/test_images/*.png ~/data/test_images/
mkdir -p ~/data/debugging_images
mv ~/data/training_images/000*.png ~/data/debugging_images/
mv ~/data/training_images/001*.png ~/data/debugging_images/
echo "done!"
```

## Step 5: Basics of Neural Networks

Work through notebooks `nn_demo_part1.ipynb` and `nn_demo_part2.ipynb`.

## Step 5-7: Training and Debugging Models with Various Tools

`step_5_to_6_part1.ipynb` runs through a logistic regression model using Sci-kit
Learn and Tensorflow based on some basic image features.

`step_5_to_8_part2.ipynb` trains a convolutional neural network using
Tensorflow and runs some debugging steps to look at pictures which were wrongly
classified.

## Step 8-9: Validation and Testing

Before proceeding, if you have been running data science on a VM without GPU,
strongly consider creating a new one with GPU. For this exercise, K80 is the
best tradeoff for its cost and run time.

Run `step_8_to_9.ipynb` to train a model, do some basic debugging, and run
validation and testing on the entire dataset.
