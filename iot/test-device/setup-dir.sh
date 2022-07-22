#!/bin/bash

if [[ -z ${1} ]]; then
	IDX="1"
else
	IDX=${1}
fi

mkdir -p \
	~/iot.storage/device${IDX}/root/dc-configs \
	~/iot.storage/device${IDX}/root/certs \
	~/iot.storage/device${IDX}/root/messages \
	~/iot.storage/device${IDX}/root/policies

mkdir -p \
	~/iot.storage/device${IDX}/root/certs/testconn \
	~/iot.storage/device${IDX}/root/certs/pubsub \
	~/iot.storage/device${IDX}/root/certs/jobs 

chmod 700 \
	~/iot.storage/device${IDX}/root/certs/testconn \
	~/iot.storage/device${IDX}/root/certs/pubsub \
	~/iot.storage/device${IDX}/root/certs/jobs

