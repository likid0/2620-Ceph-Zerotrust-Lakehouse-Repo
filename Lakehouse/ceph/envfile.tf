############################
# write .compose-aws.env  ##
############################

terraform {
  required_providers {
    local = {               # tiny provider that writes files
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# Build the text we want to write
locals {
  compose_env = <<-EOT
    AWS_REGION=default
    AWS_ACCESS_KEY_ID=${aws_iam_access_key.catalog_admin_key.id}
    AWS_SECRET_ACCESS_KEY=${aws_iam_access_key.catalog_admin_key.secret}
    AWS_ENDPOINT_URL_STS=https://s3.cephlabs.com
    AWS_ENDPOINT_URL=https://s3.cephlabs.com
  EOT
}

# Emit the file next to docker-compose.yml  (path.root is the ceph/ folder)
resource "local_file" "compose_env" {
  filename = "${path.root}/../.compose-aws.env"
  content  = trimsuffix(local.compose_env, "\n")
}

output "compose_env_path" {
  value = local_file.compose_env.filename
}

