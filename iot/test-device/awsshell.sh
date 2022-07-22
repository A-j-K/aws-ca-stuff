#!/bin/bash

if [[ -z ${1} ]]; then
	IDX="1"
else
	IDX=${1}
fi

if [ ! -f ~/iot.storage/aws-config ]; then
	echo "No creds found ~/iot.storage/aws-config"
	exit 1
fi

if [[ ! -d ~/iot.storage/device${IDX} ]]; then
	echo "No IoT base volumes to mount. Read the README.md"
	exit 1
fi

docker run \
	--rm=true \
	--name AWS-IOT-DEVICE-${IDX} \
	-v ~/iot.storage/aws-config:/root/.aws/config \
	-v ~/iot.storage/device${IDX}/root/dc-configs:/root/dc-configs \
	-v ~/iot.storage/device${IDX}/root/certs:/root/certs \
	-v ~/iot.storage/device${IDX}/root/messages:/root/messages \
	-v ~/iot.storage/device${IDX}/root/policies:/root/policies \
	-it awsiotdevice:latest \
	bash

