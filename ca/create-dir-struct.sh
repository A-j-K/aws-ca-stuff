#!/bin/bash

DIR="/rootb/ca"

if [[ -d $DIR ]]; then
	echo "The 'ca' directory allready exists"
	exit 1
else
	mkdir $DIR || exit 1
fi

pushd $DIR
cp ../openssl-root.cnf openssl.cnf 
mkdir certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
popd

pushd $DIR
mkdir intermediate
cp ../openssl-intermediate.cnf intermediate/openssl.cnf
pushd intermediate
mkdir certs crl csr newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
popd

popd

