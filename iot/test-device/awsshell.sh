#!/bin/bash

if [ ! -f ~/iot.aws ]; then
	echo "No creds found ~/iot.aws"
	exit 1
fi

if [[ ! -d ~/iot.storage ]]; then
	echo "No IoT base volumes to mount. Read the README.md"
	exit 1
fi

if [[ -z ${1} ]]; then
	IDX="1"
else
	IDX=${1}
fi

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

