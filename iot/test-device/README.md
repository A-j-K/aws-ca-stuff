# AWS IoT Test Device

## Getting Started

Much of the IoT documentation refers to using devices such as the Raspberry PI as an IoT device to evaluate the AWS IoT Client.

This isn't always so easy. So this section allows to build an IoT device as a Docker Container. You can then use these as multiple devices.

Use the _build_iot.sh_ script to build the container image.

The _awsshell.sh_ script is an example of how to run a single image. Before running it you need to setup some directories and then mount them into the container using the -v command line option. This script shows an example :-

```
docker run \
        --rm=true \
        -v ~/iot.storage/aws-config:/root/.aws/config \
        -v ~/iot.storage/device${IDX}/root/dc-configs:/root/dc-configs \
        -v ~/iot.storage/device${IDX}/root/certs:/root/certs \
        -v ~/iot.storage/device${IDX}/root/messages:/root/messages \
        -v ~/iot.storage/device${IDX}/root/policies:/root/policies \
        -it awsiotdevice:latest \
        --name AWS-IOT-DEVICE-${IDX} \
        bash
```

Ensure you [read the getting started guide](https://docs.aws.amazon.com/iot/latest/developerguide/iot-gs.html).

The purpose and content of the following directories can be found [here](https://docs.aws.amazon.com/iot/latest/developerguide/iot-dc-install-download.html#iot-dc-install-dc-files). Ensure you read these documents and setup the directories correctly before attempting to run a container.

* /root/dc-configs
* /root/certs
* /root/messages
* /root/policies

You can run multiple conatiners to mimic multiple IoT devices but each container will need its own set of directories configured and mounted (-v) accordingly, do not try to share directories between containers, they must be isolated.


* /root/.aws/config

This directory requires AWS credentials, read more about this [here](https://docs.aws.amazon.com/iot/latest/developerguide/iot-dc-install-provision.html). Note, it uses the Raspberry PI as an example but the information holds true for what you need to inject credentials into your container. Note, this mount (-v) can be shared across multiple containers so all use the same basic AWS Access credentials.

The _setup-dir.sh_ shell file can be used to create the directory structure. It's up to you to fill these directories with the required startup files for the device. After running this script twice (__./setup-dir.sh__ 1 and __./setup-dir.sh 2__) you should find the directory stricture as shown below.

```
/home/user/iot.storage/
├── device1
│   └── root
│       ├── certs
│       │   ├── jobs
│       │   ├── pubsub
│       │   └── testconn
│       ├── dc-configs
│       ├── messages
│       └── policies
└── device2
    └── root
        ├── certs
        │   ├── jobs
        │   ├── pubsub
        │   └── testconn
        ├── dc-configs
        ├── messages
        └── policies
```

Ensure you read the linked documents here and populate each directory with the required files.

## Running the IoT Device

The following section can be found in the [AWS documentation](https://docs.aws.amazon.com/iot/latest/developerguide/iot-dc-testconn-provision.html#iot-dc-testconn-provision-aws).

### Check AWS Creds

The previous section was about setting up to execute the conatiner. Note that when the conatiner is run it is in foreground mode. To run multiple containers you will need multiple ssh/terminal windows to run each container in.


To test our AWS creds were injected correctly we begin by running a test container:-
```
$ ./awsshell.sh
root@b3358ccac92e:~#
```
_Note, your shell command will look like this but the container ID will be your shell prompt._

Test the AWS Creds. _Note, before running this you will have needed to have created an AWS IoT instance using the AWS Console_
```
$ aws iot describe-endpoint --endpoint-type IoT:Data-ATS
{
    "endpointAddress": "a2************-ats.iot.eu-west-1.amazonaws.com"
}
```
_(Note, I starred out my endpoint for security reasons, you will recieve back your endpoint)_

### Register your device

```
$ aws iot create-thing --thing-name $DEVNAME
{
    "thingName": "DEVICE1",
    "thingArn": "arn:aws:iot:eu-west-1:85**********:thing/DEVICE1",
    "thingId": "ee6cde80-****-****-****-************"
}
```
_(note, DEVNAME is an enviroment variable defined by the awsshell.sh script)_

This command will register your device and on success return a JSON string with details about your device registration. Make a note of these.

Once you reach this point you can now continue following the [standard AWS tutorial](https://docs.aws.amazon.com/iot/latest/developerguide/iot-dc-testconn-provision.html#iot-dc-testconn-provision-aws). 

When you follow this tutorial you will add various configuration files as described. These will be stored in the directory structure that is mounted into your container. This ensures any work you do during the tutorial is maintained when the container is terminated thus allowing you to return to the tutorials any any time by starting the container again.

Good luck and happy MQTTing.






