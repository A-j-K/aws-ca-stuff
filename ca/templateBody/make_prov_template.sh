#!/bin/bash

if [[ -z $1 || -z $2 ]]; then
	echo "$0 <aws policy arm> <template.json>"
	exit 1
fi

if [[ ! -f $2 ]]; then
	echo "$2 was not a file"
	exit 1
fi

echo "{"
echo "    \"roleArn\": \"$1\","
echo "    \"templateBody\":\"$(cat $2 | jq '@json')\""
echo "}"


