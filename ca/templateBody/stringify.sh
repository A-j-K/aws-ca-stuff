#!/bin/bash

if [[ -z $1 ]]; then
	echo "Please supply the filename of the JSON to stringify"
	exit -1
fi

cat $1 | jq '@json'


