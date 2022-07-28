#!/bin/bash

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DIR="/rootb/ca"

if [[ -d ${DIR} ]]; then
	echo "The 'ca' directory allready exists"
	exit 1
else
	mkdir ${DIR} || exit 1
fi

pushd ${DIR}
cp ${SCRIPTDIR}/openssl-root.cnf openssl.cnf 
cp ${SCRIPTDIR}/templateBody/register-ca-cert-template.json register-ca-cert-template.json
mkdir certs crl newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
popd

pushd ${DIR}
mkdir intermediate
cp ${SCRIPTDIR}/openssl-intermediate.cnf intermediate/openssl.cnf
pushd intermediate
mkdir certs crl csr newcerts private
chmod 700 private
touch index.txt
echo 1000 > serial
popd

popd

