#!/bin/bash

if [ ! -f ~/iot.aws ]; then
	echo "No creds found ~/iot.aws"
	exit 1
fi

if [[ ! -d ~/iot.storage ]]; then
	echo "No IoT base volumes to mount. Read the README.md"
	exit 1
fi

docker run \
	--rm=true \
	-v ~/iot.aws:/root/.aws/config \
	-v ~/iot.storage/root/dc-configs:/root/dc-configs \
	-v ~/iot.storage/root/certs:/root/certs \
	-v ~/iot.storage/root/messages:/root/messages \
	-v ~/iot.storage/root/policies:/root/policies \
	-it awsiotdevice:latest \
	bash

