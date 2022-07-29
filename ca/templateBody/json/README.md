# JSON documents

* role.json

This JSON document is used part of the registration template for the IAM policy that is also required. This represents an example role.

* templateBody.json

This JSON document from the [example supplied by AWS](https://docs.aws.amazon.com/iot/latest/developerguide/jit-provisioning.html).

* policy.json

Inspection of the templateBody.json file will show an embedded policy in JSON.stringyfy format. This JSON document is that document and the stringyfied version can be acquired this:-

```
$ cat policy.json | jq -r '@json'
```

The output of which can be copied into the templateBody.json **before** that document itself is then also JSON.stringyfied

 


