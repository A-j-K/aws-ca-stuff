# AWS IoT Test Device


Much of the IoT documentation refers to using devices such as the Raspberry PI as an IoT device to evaluate teh AWS IoT Client.

This isn't always so easy. So this section allows to build an IoT device as a Docker Container. You can then use these as multiple devices.

Use the _build_iot.sh_ script to build the container image.

The _awsshell.sh_ script is an example of how to run a single image. Before running it you need to setup some directories and then mount them into the container using the -v command line option. This script shows an example :-

```
docker run \
	--rm=true \
	-v ~/iot.aws:/root/.aws/config \
	-v ~/iot.storage/root/dc-configs:/root/dc-configs \
	-v ~/iot.storage/root/certs:/root/certs \
	-v ~/iot.storage/root/messages:/root/messages \
	-v ~/iot.storage/root/policies:/root/policies \
	-it awsiotdevice:latest \
	bash
```

Ensure you [read the getting started guide](https://docs.aws.amazon.com/iot/latest/developerguide/iot-gs.html).

The purpose and content of the following directories can [can be found here](https://docs.aws.amazon.com/iot/latest/developerguide/iot-dc-install-download.html#iot-dc-install-dc-files). Ensure you read these documents and setup the directories correctly before attempting to run a container.

* /root/dc-configs
* /root/certs
* /root/messages
* /root/policies

You can run multiple conatiners to mimic multiple IoT devices but each container will need its own set of directories configured and mounted (-v) accordingly, do not try to share directories between containers, they must be isolated.


* /root/.aws/config

This directory requires AWS credentials, read more about this [here](https://docs.aws.amazon.com/iot/latest/developerguide/iot-dc-install-provision.html). Note, it uses the Raspberry PI as an example but the information holds true for what you need to inject credentials into your container. Note, this mount (-v) can be shared across multiple containers so all use the same basic AWS Access credentials.

