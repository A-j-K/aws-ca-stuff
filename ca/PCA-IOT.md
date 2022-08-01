# Using AWS ACM PCA for AWS IoT JIT Provisioning


## Our Private CA

Create a root private key and cert

```
$ openssl genrsa -aes256 -out private/ca.key.pem 2048
$ chmod 400 private/ca.key.pem
$ openssl req \
	-new -x509 -days 73000 \
	-config openssl.cnf \
	-key private/ca.key.pem \
	-sha256 -extensions v3_ca \
	-out certs/ca.cert.pem
chmod 444 certs/ca.cert.pem
```

Create our CA within AWS

```
$ aws acm-pca create-certificate-authority \
	--certificate-authority-configuration file://acm-pca-config.json \
	--certificate-authority-type "ROOT" \
	--idempotency-token $(date +'%Y%m%d%H%M%S') \
	> /var/tmp/ca/ca-root-arn.json

$ CA_ARN=$(cat /var/tmp/ca/ca-root-arn.json | jq -r '.CertificateAuthorityArn')
$ echo $CA_ARN
```

Verify the CA and check it is in PENDING_CERTIFICATE state

```
$ aws acm-pca describe-certificate-authority \
	--certificate-authority-arn $CA_ARN \
	| jq -r '.CertificateAuthority.Status'
PENDING_CERTIFICATE
```

Install a self-signed certificate
(this is annoying getting Subject attributes to line up, use console!)
```
$ aws acm-pca import-certificate-authority-certificate \
	--certificate-authority-arn $CA_ARN \
	--certificate file://certs/ca.cert.pem
	
```

## Create an IoT verification cert

Get IoT's registration code

```
$ aws iot get-registration-code \
        > /var/tmp/ca/iot-registration-code.json
$ IOT_REG_CODE=$(cat /var/tmp/ca/iot-registration-code.json | jq -r '.registrationCode')
$ echo $IOT_REG_CODE
```

Create a cert set for IoT

```
$ openssl genrsa -out private/iot-ca.key 2048
$ openssl req -new  \
	-key private/iot-ca.key \
	-subj "/CN=$IOT_REG_CODE" \
	-out csr/iot-ca.csr
```

Get PCA to issue a v3 cert

```
$ TEMPLATE_ARN="arn:aws:acm-pca:::template/SubordinateCACertificate_PathLen0/V1"

$ aws acm-pca issue-certificate \
        --certificate-authority-arn "$CA_ARN" \
	--template-arn $TEMPLATE_ARN \
        --csr file://csr/iot-ca.csr \
        --signing-algorithm SHA256WITHRSA \
        --validity Value=3640,Type="DAYS" \
	> /var/tmp/ca/iot-ca-cert-arn.json
$ IOT_CERT_ARN=$(cat /var/tmp/ca/iot-ca-cert-arn.json | jq -r '.CertificateArn')
$ echo $IOT_CERT_ARN

# Get the cert
$ aws acm-pca get-certificate \
	--certificate-authority-arn "$CA_ARN" \
	--certificate-arn "$IOT_CERT_ARN" \
	> /var/tmp/ca/iot-ca-cert.json
$ cat /var/tmp/ca/iot-ca-cert.json | jq -r '.Certificate' > certs/iot-ca.crt
$ cat /var/tmp/ca/iot-ca-cert.json | jq -r '.CertificateChain' > certs/iot-ca-chain.crt
```

Register the IoT CA Cert

```
$ aws iot register-ca-certificate \
	--ca-certificate file://certs/iot-ca-chain.crt \
	--verification-certificate file://certs/iot-ca.crt \
	--set-as-active \
	--allow-auto-registration \
	--tags 'Key=OWNER,Value=ajk' \
	> /var/tmp/ca/register-ca-certificate.json
$ AWS_IOT_CERTIFICATE_ARN=$(cat /var/tmp/ca/register-ca-certificate.json | jq -r '.certificateArn')
$ AWS_IOT_CERTIFICATE_ID=$(cat /var/tmp/ca/register-ca-certificate.json | jq -r '.certificateId')
```

## Add JIT provisioning template to IoT CA

An IAM Role is required

```
$ aws iam create-role \
	--role-name "ACME-IOT-JIT-PROV" \
	--assume-role-policy-document "file://templateBody/json/role.json" \
	> /var/tmp/ca/role-details.json
$ ROLE_ARN=$(cat /var/tmp/ca/role-details.json | jq -r .Role.Arn)
```

We then need the templateBody. A sample exists in templateBody/json/templateBody.json and we JSON.stringify thus:-

```
$ cat templateBody/json/templateBody.json | jq '@json'
"{\"Parameters\":{\"AWS::IoT::Certificate::CommonName\":{\"Type\":\"String\"},\"AWS::IoT::Certificate::OrganizationName\":{\"Type\":\"String\"},\"AWS::IoT::Certificate::Id\":{\"Type\":\"String\"}},\"Resources\":{\"thing\":{\"Type\":\"AWS::IoT::Thing\",\"Properties\":{\"ThingName\":{\"Ref\":\"AWS::IoT::Certificate::CommonName\"},\"ThingTypeName\":\"UnifiedAgent\"},\"OverrideSettings\":{\"AttributePayload\":\"MERGE\",\"ThingTypeName\":\"REPLACE\",\"ThingGroups\":\"DO_NOTHING\"}},\"certificate\":{\"Type\":\"AWS::IoT::Certificate\",\"Properties\":{\"CertificateId\":{\"Ref\":\"AWS::IoT::Certificate::Id\"},\"Status\":\"ACTIVE\"},\"OverrideSettings\":{\"Status\":\"DO_NOTHING\"}},\"policy\":{\"Type\":\"AWS::IoT::Policy\",\"Properties\":{\"PolicyDocument\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Action\\\":[\\\"iot:Subscribe\\\",\\\"iot:Connect\\\",\\\"iot:Publish\\\",\\\"iot:UpdateThingShadow\\\",\\\"iot:CreateTopicRule\\\"],\\\"Resource\\\":[\\\"*\\\"]}]}\"}}}}"
```

Finally using a text editor to create the final document **prov.json** ready to apply the provisioning template which looks like this:-

```
{
    "roleArn" : " <the IAM Role ARN from above> ",
    "templateBody": " <the stringified output from above> "
}
```

```
$ aws iot update-ca-certificate \
	--certificate-id $AWS_IOT_CERTIFICATE_ID \
	--registration-config file://prov.json 
```

There is no output from this command unless it was unsuccessful. To verify the template was actually attached do the following and study the output:-

```
$ aws iot describe-ca-certificate \
	--certificate-id $AWS_IOT_CERTIFICATE_ID \
	| jq '.registrationConfig.templateBody'
```

## Issue a device cert and use

```
# Note, this would normally be done on the device and the CSR sent
# to the service as part of the token to cert sequence. We use this
# shell purely for PoC
$ openssl genrsa -out private/device.key 2048
$ openssl req -new -sha256 -key private/device.key -out csr/device.csr
```

Now get PCA to issue a certificate

```
$ aws acm-pca issue-certificate \
        --certificate-authority-arn "$CA_ARN" \
        --csr file://csr/device.csr \
        --signing-algorithm SHA256WITHRSA \
        --validity Value=3640,Type="DAYS" \
	> /var/tmp/ca/device-cert-arn.json
$ DEVICE_CERT_ARN=$(cat /var/tmp/ca/device-cert-arn.json | jq -r '.CertificateArn')
```

Get the certificate

```
$ aws acm-pca get-certificate \
	--certificate-authority-arn "$CA_ARN" \
	--certificate-arn "$DEVICE_CERT_ARN" \
	> /var/tmp/ca/device-cert.json
```

We now use this to connect a device to IoT


$ aws-iot-device-client \
        --enable-sdk-logging \
        --log-level DEBUG \
        --sdk-log-level DEBUG \
        --key certs/testconn/device.key \
        --cert certs/testconn/device_chain.crt \
        --thing-name $THING_NAME \
        --endpoint $EP

$ aws-iot-device-client \
        --enable-sdk-logging \
        --log-level DEBUG \
        --sdk-log-level DEBUG \
        --key certs/testconn/device.key \
        --cert certs/testconn/device_chain.crt \
        --thing-name $THING_NAME \
        --endpoint $EP \
	--publish-topic FOO \
	--publish-file foo.txt




