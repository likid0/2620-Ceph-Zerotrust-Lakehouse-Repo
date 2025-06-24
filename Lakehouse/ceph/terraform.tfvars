# Ceph object-gateway (RGW) HTTPS endpoint, used for S3 **and** STS/IAM calls
ceph_endpoint       = "https://s3.example.com"

# Where Terraform’s AWS provider will read your access-key/secret-key pair
credentials_path    = "~/.aws/credentials"
credentials_profile = "polaris-root"

# Name of the bucket that will become Polaris’ warehouse
bucket_name         = "polarisdemo"

# The numerical “account ID” that Ceph assigns when you ran `radosgw-admin account create`
account_arn         = "RGW9470590896XXXX"

# Object-storage URI the Polaris container should treat as its warehouse
location            = "s3://polarisdemo"
