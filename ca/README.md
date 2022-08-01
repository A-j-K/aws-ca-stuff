# POC Root CA demo

## Goal:

1. Create a Private CA
2. Create an intermediate certificate and install into AWS IoT CA Manager
3. Use AWS ACM-PCA and AWS ACM to sign device CSR certs
   * Get an AWS ACM-PCA CSR and sign with our ROOT cert
   * Use that to allow AWS ACM to sign the CSR 
4. Register that device CRT with IoT
5. Use the device CRT with both AWS IoT and your Private Company hosted services

## Requirements

To follow this document you need

* [AWS CLI](https://aws.amazon.com/cli/) installed
* [jq](https://manpages.ubuntu.com/manpages/bionic/man1/jq.1.html) installed
* [openssl](https://www.openssl.org/) installed

## Proceedure

Note, in both config files:-

* the directory was set to "/rootb/ca"
* the defaults for Cert attributes were altered

Use the script to create the directory structure and files associated with CA management
```
$ create-dir-struct.sh
```

## Key and Cert Generation Flow


![Certificate Authority Flow](images/2022-07-26_10h58_29.png)


## Create the Root key and Cert

### Root key (1)
Use a strong password

```
$ cd /rootb/ca
$ openssl genrsa -aes256 -out private/ca.key.pem 4096
$ chmod 400 private/ca.key.pem
```

### Create the Certificate (2)

```
cd /rootb/ca
$ openssl req \
	-new -x509 -days 73000 \
	-config openssl.cnf \
	-key private/ca.key.pem \
	-sha256 -extensions v3_ca \
	-out certs/ca.cert.pem
$ chmod 444 certs/ca.cert.pem
```

### Verify root certificate

```
$ openssl x509 -noout -text -in certs/ca.cert.pem
```

Insure the the v3 extensions are applied similar to the following:-
```
        X509v3 extensions:
            X509v3 Subject Key Identifier:
                8A:E4:94:16:2E:20:62:45:FE:E4:89:A1:A1:3C:AA:21:F9:A1:D6:24
            X509v3 Authority Key Identifier:
                keyid:8A:E4:94:16:2E:20:62:45:FE:E4:89:A1:A1:3C:AA:21:F9:A1:D6:24

            X509v3 Basic Constraints: critical
                CA:TRUE
            X509v3 Key Usage: critical
                Digital Signature, Certificate Sign, CRL Sign
```

## Details

```
Root key  : private/ca.key.pem
Root cert : certs/ca.cert.pem
```

# AWS ACM PCA

We now create a Private CA using AWS ACM PCA.

```
$ cd /rootb/ca
$ mkdir -p /var/tmp/ca
$ aws acm-pca create-certificate-authority \
	--certificate-authority-configuration file://acm-pca-config.json \
	--certificate-authority-type "SUBORDINATE" \
	--idempotency-token $(date +'%Y%m%d%H%M%S') \
	> /var/tmp/ca/CertificateAuthorityArn.json
$ PCA_CA_ARN=$(cat /var/tmp/ca/CertificateAuthorityArn.json | jq -r '.CertificateAuthorityArn')
$ echo $PCA_CA_ARN
```

Verify the PCA

```
$ cd /rootb/ca
$ aws acm-pca describe-certificate-authority \
	--certificate-authority-arn $PCA_CA_ARN
```

Note, it should say that the status is PENDING_CERTIFICATE:-

```
$ aws acm-pca describe-certificate-authority \
        --certificate-authority-arn $PCA_CA_ARN \
	| jq -r '.CertificateAuthority.Status'
PENDING_CERTIFICATE
```

Now we acquire from AWS ACM PCA a certificate CSR that we must sign so that AWS can use it's own certificate to sign device certs and pass on our private CA trust chain.

```
cd /rootb/ca
$ aws acm-pca get-certificate-authority-csr \
	--output text \
	--certificate-authority-arn $PCA_CA_ARN \
	> csr/aws-acm-pca.csr.pem
$ chmod 400 csr/aws-acm-pca.csr.pem
```

and sign it with our CA cert 

```
$ cd /rootb/ca 
$ openssl ca -config openssl.cnf \
	-extensions v3_intermediate_ca \
	-days 7300 \
	-notext \
	-md sha256 \
	-in csr/aws-acm-pca.csr.pem \
	-out certs/aws-acm-pca.cert.pem
```

Now we install this certificate into the AWS ACM PCA so it can issue certs on our behalf

```
$ cd /rootb/ca
$ aws acm-pca import-certificate-authority-certificate \
	--certificate-authority-arn $PCA_CA_ARN \
	--certificate file://certs/aws-acm-pca.cert.pem \
	--certificate-chain file://certs/ca.cert.pem
```

There is no return from this command unless an error has occured. Let's verify all is well:-

```
$ cd /rootb/ca
$ aws acm-pca describe-certificate-authority \
	--certificate-authority-arn $PCA_CA_ARN \
	| jq -r '.CertificateAuthority.Status'
ACTIVE
```

We now have a managed subordinate AWS ACM PCA managed system to issue certificates on our behalf.

# AWS IoT CA

In this section we will use our CA to create a certificate for the AWS IoT CA

To register a CA verification certificate with AWS IoT we need to acquire the registration key which is used in the CommonName field of the certificate.

```
$ aws iot get-registration-code \
	> /var/tmp/ca/iot-registration-code.json
$ IOT_REG_CODE=$(cat /var/tmp/ca/iot-registration-code.json | jq -r '.registrationCode')
$ echo $IOT_REG_CODE
e3f3************************************************************
```

### Create the AWS IoT Certs

```
$ openssl req -nodes -new -newkey rsa:2048 \
            -keyout private/iot-reg.key \
            -out csr/iot-reg.csr \
            -subj "/CN=$IOT_REG_CODE"
```

We now sign this CSR with our CA 

```
$ cd /rootb/ca
$ openssl ca -config openssl.cnf -extensions v3_intermediate_ca \
      -days 7300 -notext -md sha256 \
      -in csr/iot-reg.csr \
      -out certs/iot-reg.crt
$ chmod 444 certs/iot-reg.crt
```

We can now import this into AWS IoT

```
$ cd /rootb/ca
$ aws iot register-ca-certificate \
	--ca-certificate file://certs/ca.cert.pem \
	--verification-certificate file://certs/iot-reg.crt \
	--set-as-active \
	--allow-auto-registration \
	--tags 'Key=OWNER,Value=ajk' \
	> /var/tmp/ca/register-ca-certificate.json
$ AWS_IOT_CERTIFICATE_ARN=$(cat /var/tmp/ca/register-ca-certificate.json | jq -r '.certificateArn')
$ echo $AWS_IOT_CERTIFICATE_ARN
$ AWS_IOT_CERTIFICATE_ID=$(cat /var/tmp/ca/register-ca-certificate.json | jq -r '.certificateId')
$ echo $AWS_IOT_CERTIFICATE_ID
```

We now check it has registered with AWS IoT and is ACTIVE.
```
$ cd /rootb/ca
$ aws iot list-ca-certificates
```

The _certificateId_ should appear in the list of certificates.


## AWS IAM and IoT Provisioning

At this point certificates are installed in the correct places. The last step is to configure the AWS IoT CA to allow for [JIT provisioning](https://docs.aws.amazon.com/iot/latest/developerguide/jit-provisioning.html). This requires an IAM Role to be installed and then registering a provsioning template that leverages that IAM Role.

In otder to register the provision template we need two pieces of data, the IAM Role and the JSON.stringyfied version of the template in a JSON document like this:-

```
{ 
      "roleArn" : "arn:aws:iam::123*********:role/JITPRole"
      "templateBody" : "{\r\n    \"Parameters\" : {......................."
} 
```

An IAM Role may already exist but here we create one for demonstration purposes:-

```
$ cd /rootb/ca
$ aws iam create-role \
	--role-name "ACME-POC-IOT-JIT-PROV" \
	--assume-role-policy-document "file://templateBody/json/role.json" \
	> role-details.json
$ cat role-details.json | jq -r .Role.Arn
arn:aws:iam::85820*******:role/ACME-POC-IOT-JIT-PROV
$ ROLE_ARN=$(cat role_details.json | jq -r .Role.Arn)
$ echo $ROLE_ARN
arn:aws:iam::85820*******:role/ACME-POC-IOT-JIT-PROV
```

We then need the templateBody. A sample exists in __templateBody/json/templateBody.json__ and we JSON.stringify thus:-

```
$ cat templateBody/json/templateBody.json | jq '@json'
"{\"Parameters\":{\"AWS::IoT::Certificate::CommonName\":{\"Type\":\"String\"},\"AWS::IoT::Certificate::OrganizationName\":{\"Type\":\"String\"},\"AWS::IoT::Certificate::Id\":{\"Type\":\"String\"}},\"Resources\":{\"thing\":{\"Type\":\"AWS::IoT::Thing\",\"Properties\":{\"ThingName\":{\"Ref\":\"AWS::IoT::Certificate::CommonName\"},\"ThingTypeName\":\"UnifiedAgent\",\"ThingGroups\":[{\"Ref\":\"AWS::IoT::Certificate::OrganizationName\"}]},\"OverrideSettings\":{\"AttributePayload\":\"MERGE\",\"ThingTypeName\":\"REPLACE\",\"ThingGroups\":\"DO\_NOTHING\"}},\"certificate\":{\"Type\":\"AWS::IoT::Certificate\",\"Properties\":{\"CertificateId\":{\"Ref\":\"AWS::IoT::Certificate::Id\"},\"Status\":\"ACTIVE\"},\"OverrideSettings\":{\"Status\":\"DO\_NOTHING\"}},\"policy\":{\"Type\":\"AWS::IoT::Policy\",\"Properties\":{\"PolicyDocument\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Action\\\":[\\\"iot:Subscribe\\\",\\\"iot:Connect\\\",\\\"iot:Publish\\\",\\\"iot:UpdateThingShadow\\\",\\\"iot:CreateTopicRule\\\"],\\\"Resource\\\":[\\\"*\\\"]}]}\"}}}}"
```

Finally using a text editor to create the final document prov.json ready to apply the provisioning template which looks like this:-

```
{
    "roleArn" : " <the IAM Role ARN from above> ",
    "templateBody": " <the stringified output from above> "
}
```

The final step is to update the AWS IoT CA we created eariler and add this template:-

```
$ cd /rootb/ca
$ aws iot update-ca-certificate \
	--certificate-id $AWS_IOT_CERTIFICATE_ID \
	--registration-config file://prov.json 
```

There is no output from this command unless it was unsuccessful. To verify the template was actually attached do the following and study the output:-

```
$ cd /rootb/ca
$ aws iot describe-ca-certificate \
	--certificate-id $AWS_IOT_CERTIFICATE_ID \
	| jq '.registrationConfig.templateBody'
```

## Issue a Device Certificate

To begin the process of getting a certificate for a device the device should create a private key and a certificate signing request. Simulated here:-

```
$ openssl genrsa -out device.key 2048
$ openssl req -new -key device.key \
            -out device.csr \
            -subj "/CN=23855e5d-2443-47bc-97fc-41bb685b2ab3"
```
In the above example we did not password protect the private key. However, when a device creates the private key it should protect it via the Operating System's mechanisms to manage private keys.

**Note** that the CommonName (CN) **must** be the device GUID. Other fields for the certificate subject are yet to be defined.

We now ask AWS ACM PCA to provide a signed certificate from our Private CA:-

```
$ aws acm-pca issue-certificate \
        --certificate-authority-arn "$PCA_CA_ARN" \
        --csr file://device.csr \
        --signing-algorithm SHA256WITHRSA \
        --validity Value=364,Type="DAYS" \
	> pca.json
$ CERT_ARN=$(cat pca.json | jq -r '.CertificateArn')
```

Now [get the certificate]():-

```
$ aws acm-pca get-certificate \
	--certificate-authority-arn "$PCA_CA_ARN" \
	--certificate-arn "$CERT_ARN" \
	> cert.json
```

Notice that the returned value is a JSON object. The certs can be extracted using JQ thus:-

```
$ cat cert.json | jq -r .Certificate > device.crt
$ cat cert.json | jq -r .CertificateChain > device_chain.crt
```

We can validate that the issued certificate is for the device GUID we supplied in the CSR thus:-

```
$ openssl x509 -in device.crt -text -noout| grep "Subject:"
	Subject: C = GB, ST = Some-State, O = NABLE, CN = b197cc51-c6f2-4347-acab-577117296395
```

We can validate the chain file is actually signed by our CA signing certificate thus:-

```
$ openssl x509 -in device_chain.crt -text -noout | grep "Subject:"

	Subject: C = GB, O = ACME, OU = Arch POC, CN = ACME-CA
```

We now have the device certificate that:-
* Needs to be registered with AWS IoT
* Sent to the device to use the certificate

## Register the Device Certificate with AWS IoT

We now register tihe device certificate with AWS IoT

(note, todo, without ca?)

```
$ aws iot register-certificate \
        --certificate-pem file://device.crt \
	--ca-certificate-pem file://intermediate/certs/aws-iot-chain.cert.pem \
	> cert-reply.json
$ cat cert-reply.json | jq -r '.certificateArn' > cert-arn.txt
$ cat cert-reply.json | jq -r '.certificateId' > cert-id.txt

$ aws iot 
	--certificate-pem file://device.crt \
	--status PENDING_ACTIVATION

```


Now attach a policy to the certificate (notice here that the policy is named and not an ARN)

```
$ aws iot attach-policy \
	--policy-name "POLICY_NAME" \
	--target $(cat cert-arn.txt)
```

Finally, as a test, the certificate can be double checked:-

```
$ aws iot describe-certificate \
        --certificate-id $(cat cert-id.txt)
{
    "certificateDescription": {
        "certificateArn": "arn:aws:iot:eu-west-1:858204861084:cert/39c8e91e67e0df17d17d********************************************",
        "certificateId": "39c8e91e67e0df17d17d********************************************",
        "status": "ACTIVE",
        "certificatePem": "-----BEGIN CERTIFICATE-----\nMIIDqTCCApGgAwIBAgIRAKF******************************",
        "ownedBy": "858204******",
        "creationDate": 1658754661.42,
        "lastModifiedDate": 1658754661.42,
        "customerVersion": 1,
        "transferData": {},
        "generationId": "112cea4e-d070-4175-a9c8-***************",
        "validity": {
            "notBefore": 1658748293.0,
            "notAfter": 1690201493.0
        },
        "certificateMode": "SNI_ONLY"
    }
}
```

## Send the Device its Certificates

The last step is to return the device.crt and device_chain.crt certificates to the device to use to connect with AWS IoT.

The following describes testing an IoT connecting and registering using the certificate provided by AWS ACM PCA and a Docker Container


## References

* https://docs.aws.amazon.com/cli/latest/reference/iot
* https://docs.aws.amazon.com/cli/latest/reference/acm
* https://docs.aws.amazon.com/cli/latest/reference/acm-pca
* https://jamielinux.com/docs/openssl-certificate-authority/introduction.html
* https://aws.amazon.com/blogs/iot/how-to-manage-iot-device-certificate-rotation-using-aws-iot/
* https://aws.amazon.com/blogs/mobile/use-your-own-certificate-with-aws-iot
* https://catalog.us-east-1.prod.workshops.aws/workshops/7c2b04e7-8051-4c71-bc8b-6d2d7ce32727/en-US/provisioning-options/just-in-time-provisioning
* https://aws.amazon.com/blogs/iot/just-in-time-registration-of-device-certificates-on-aws-iot/
* https://docs.aws.amazon.com/acm-pca/latest/userguide/UsingTemplates.html

## Notes (ignore these)

```
$ aws-iot-device-client \
	--enable-sdk-logging \
	--log-level DEBUG \
	--sdk-log-level DEBUG \
	--key certs/testconn/device.key \
	--cert certs/testconn/deviceAndCACert.crt \
	--thing-name $THING_NAME \
	--endpoint $EP

	--cert certs/testconn/device.crt \
	--root-ca certs/testconn/device_chain.crt \
	--root-ca certs/testconn/chain.crt \
	--root-ca certs/testconn/pca.crt \

$ echo | openssl s_client \
	-CAfile certs/testconn/chain.crt \
	-cert certs/testconn/device.crt \
	-key certs/testconn/device.key \
	-connect $EP


```
