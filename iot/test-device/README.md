# AWS IoT Test Device

## Getting Started

Much of the IoT documentation refers to using devices such as the Raspberry PI as an IoT device to evaluate teh AWS IoT Client.

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


The previous section was about setting up to execute the conatiner. Note that when the conatiner is run it is in foreground mode. To run multiple containers you will need multiple ssh/terminal windows to run each container in.




