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

## Create the Intermediate key and Intermediate Cert

### Create the Intermediate key (3)

```
$ cd /rootb/ca
$ openssl genrsa -aes256 -out intermediate/private/intermediate.key.pem 4096
```

### Create the Intermediate CSR (4)

```
$ cd /rootb/ca
$ openssl req -config intermediate/openssl.cnf -new -sha256 \
      -key intermediate/private/intermediate.key.pem \
      -out intermediate/csr/intermediate.csr.pem
```

#### Sign the CSR with the ROOT KEY to create the Cert (5)

```
$ cd /rootb/ca
$ openssl ca -config openssl.cnf -extensions v3_intermediate_ca \
      -days 7300 -notext -md sha256 \
      -in intermediate/csr/intermediate.csr.pem \
      -out intermediate/certs/intermediate.cert.pem
$ chmod 444 intermediate/certs/intermediate.cert.pem
```

Create the intermediate chain file. Note the order, the root cert is last in the chain.
```
$ cd /rootb/ca
$ cat intermediate/certs/intermediate.cert.pem \
      certs/ca.cert.pem > intermediate/certs/ca-chain.cert.pem
$ chmod 444 intermediate/certs/ca-chain.cert.pem
```

## Details

```
Root key  : private/ca.key.pem
Root cert : certs/ca.cert.pem
Int  key  : intermediate/private/intermediate.key.pem
Int  cert : intermediate/certs/intermediate.cert.pem
Int chain : intermediate/certs/ca-chain.cert.pem
```

# AWS IoT CA

In this section we will use the previous CA we created to create a set of Certs for AWS IoT.
It is assumed you already have AWS credentials setup as the default profile.

To register a CA verification certificate with AWS IoT we need to acquire the registration key which is used in the CommonName field of the certificate.

```
$ aws iot get-registration-code 
{
    "registrationCode": "e3f3XXXXXXXXXXX20XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
}
```
To make using this document simpler we will assign values returned by AWS to enviroment variables:-

```
$ REG_CODE=$(aws iot get-registration-code | jq -r '.registrationCode')
$ echo $REG_CODE
```

Make a note of the registartion code to be used later.

### Create the AWS IoT  

* Common Name []: [reg code from previous step above]

```
$ cd /rootb/ca
$ openssl req -config intermediate/openssl.cnf -new -sha256 \
      -key intermediate/private/intermediate.key.pem \
      -out intermediate/csr/aws-iot.csr.pem
```

#### Sign the CSR with the Intermediate KEY to create the Cert

```
$ cd /rootb/ca
$ openssl ca -config intermediate/openssl.cnf -extensions v3_intermediate_ca \
      -days 7300 -notext -md sha256 \
      -in intermediate/csr/aws-iot.csr.pem \
      -out intermediate/certs/aws-iot.cert.pem
$ chmod 444 intermediate/certs/aws-iot.cert.pem
```

Create the intermediate chain file. Note the order, the root cert is last in the chain.
```
$ cd /rootb/ca
$ cat intermediate/certs/aws-iot.cert.pem \
      intermediate/certs/intermediate.cert.pem \
      certs/ca.cert.pem > intermediate/certs/aws-iot-chain.cert.pem
$ chmod 444 intermediate/certs/aws-iot-chain.cert.pem
```

This process created two new files (we ignore the csr file):-

```
intermediate/certs/aws-iot.cert.pem
intermediate/certs/aws-iot-chain.cert.pem
```

We now register these with AWS IoT (note at the end we assign the returned ARN to a shell var as we need it later on)

```
cd /rootb/ca

$ aws iot register-ca-certificate \
	--ca-certificate file://intermediate/certs/intermediate.cert.pem \
	--verification-certificate file://intermediate/certs/aws-iot-chain.cert.pem \
	--set-as-active \
	--allow-auto-registration \
	--tags 'Key=OWNER,Value=ajk'
# returns:-
{
    "certificateArn": "arn:aws:iot:eu-west-1:8582********:cacert/2ccc************************************************************",
    "certificateId": "2ccc************************************************************"
}
# Place the ARN in an ENV VAR
$ AWS_IOT_CERTIFICATE_ARN="arn:aws:iot:eu-west-1:8582********:cacert/2ccc************************************************************"
$ AWS_IOT_CERTIFICATE_ID="2ccc************************************************************"
```

We now check it has registered with AWS IoT and is ACTIVE.
```
$ cd /rootb/ca
$ aws iot list-ca-certificates
```

The _certificateId_ should appear in the list of certificates.

### Add registration Template to IoT CA

In order for devices issues with Certs signed by our CA we must associate the CA with a 
[registration configuration](https://docs.aws.amazon.com/iot/latest/developerguide/jit-provisioning.html). (Also see [Provisioning Templates](https://docs.aws.amazon.com/iot/latest/developerguide/provision-template.html))

ToDo!!!

```
$ cd/rootb/ca
$ aws iot update-ca-certificate \
	--certificate-id "$AWS_IOT_CERTIFICATE_ARN" \
	--registration-config file://register-ca-cert-template.json
```

# AWS ACM Private CA

In this section we will insert our intermediate signing CA key and certificates into ACM.

## Create a Private Certificate Authority

We begin by creating a root CA with AWS ACM Private CA. In this example we use a basic configuration file acm-pca-config.json

```
$ cd /rootb
$ aws acm-pca create-certificate-authority \
	--certificate-authority-configuration file://acm-pca-config.json \
	--certificate-authority-type "SUBORDINATE" \
	--idempotency-token $RANDOM 
# returns
{
    "CertificateAuthorityArn": "arn:aws:acm-pca:eu-west-1:8582********:certificate-authority/9e1f9317-****-****-****-************"
}
$ export CA_ARN="arn:aws:acm-pca:eu-west-1:8582********:certificate-authority/9e1f9317-****-****-****-************"
```

Verify this PCA
```
$ cd /rootb
$ aws acm-pca describe-certificate-authority \
	--certificate-authority-arn $CA_ARN
```

If needed, all CA certs can be listed thus:
```
$ aws acm-pca list-certificate-authorities
```

The description above should show "Status": "PENDING_CERTIFICATE".

Now we acquire from AWS ACM PCA a certificate CSR that we must sign so that AWS can use it's own certificate to sign device certs and pass on our private CA trust chain.

```
$ cd /rootb/ca
$ aws acm-pca get-certificate-authority-csr \
	--output text  \
	--certificate-authority-arn $CA_ARN \
	> intermediate/csr/aws-acm-pca.csr.pem
$ chmod 400 intermediate/csr/aws-acm-pca.csr.pem
```

and sign it with our intermediate cert

```
$ cd /rootb/ca 
$ openssl ca -config openssl.cnf \
	-extensions v3_intermediate_ca \
	-days 7300 \
	-notext \
	-md sha256 \
	-in intermediate/csr/aws-acm-pca.csr.pem \
	-out intermediate/certs/aws-acm-pca.cert.pem
```

### Install Certificates into the PCA

```
$ cd /rootb/ca
$ aws acm-pca import-certificate-authority-certificate \
	--certificate-authority-arn $CA_ARN \
	--certificate file://intermediate/certs/aws-acm-pca.cert.pem \
	--certificate-chain file://certs/ca.cert.pem
```

If we now again describe the AWS PCA CA we will see that its status has changed from "PENDING_CERTIFICATE" to "ACTIVE"
```
$ aws acm-pca describe-certificate-authority \
	--certificate-authority-arn $CA_ARN \
	| jq '.CertificateAuthority.Status'
"ACTIVE"
```

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
$ openssl req -new -sha256 -key device.key -out device.csr
```
In the above example we did not password protect the private key. However, when a device creates the private key it should protect it via the Operating System's mechanisms to manage private keys.

**Note** that the CommonName (CN) **must** be the device GUID. Other fields for the certificate subject are yet to be defined.

We now ask AWS ACM PCA to provide is with a signed certificate from our Private CA:-

```
$ aws acm-pca issue-certificate \
        --certificate-authority-arn "$CA_ARN" \
        --csr file://device.csr \
        --signing-algorithm SHA256WITHRSA \
        --validity Value=364,Type="DAYS"
{
    "CertificateArn": "arn:aws:acm-pca:eu-west-1:858204861084:certificate-authority/80d65aa0-041d-441b-a731-a556ed0f23e8/certificate/a169*************"
}
$ export CERT_ARN="arn:aws:acm-pca:eu-west-1:858204861084:certificate-authority/80d65aa0-041d-441b-a731-a556ed0f23e8/certificate/a169***********
**"
```

Now [get the certificate]():-

```
$ aws acm-pca get-certificate \
	--certificate-authority-arn "$CA_ARN" \
	--certificate-arn "$CETR_ARN" \
	> cert.json
```

Notice that the returned value is a JSON object. The certs can be extracted using JQ thus:-

```
$ cat cert.json | jq -r .Certificate > device.crt
$ cat cert.json | jq -r .CertificateChain > device_chain.crt
```

We can validate that the issued certificate is for the device GUID we supplied in teh CSR thus:-

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
$ aws iot register-certificate-without-ca \
        --status ACTIVE \
        --certificate-pem file://device.crt \
	> cert-reply.json
$ cat cert-reply.json | jq -r '.certificateArn' > cert-arn.txt
$ cat cert-reply.json | jq -r '.certificateId' > cert-id.txt
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

