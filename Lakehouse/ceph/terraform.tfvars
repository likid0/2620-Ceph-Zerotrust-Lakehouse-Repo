# Ceph object-gateway (RGW) HTTP endpoint, used for S3 **and** STS/IAM calls
ceph_endpoint       = "http://ceph-node2"

# Where Terraform’s AWS provider will read your access-key/secret-key pair
credentials_path    = "~/.aws/credentials"
credentials_profile = "polaris-root"

# Name of the bucket that will become Polaris’ warehouse
bucket_name         = "polarisdemo"

# The numerical “account ID” that Ceph assigns when you ran `radosgw-admin account create`
####################
### Change the Account ID for the One created in your LAB Env.
####################
account_arn         = "RGWXXXXXXXXXX"

# Object-storage URI the Polaris container should treat as its warehouse
location            = "s3://polarisdemo"
