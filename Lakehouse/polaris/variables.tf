variable "polaris_host" {
  description = "The host address for the Polaris server"
  type        = string
  default     = "localhost"
}

variable "polaris_scheme" {
  description = "The scheme (http or https) for connecting to the Polaris server"
  type        = string
  default     = "http"
}

variable "polaris_port" {
  description = "The port for connecting to the Polaris server"
  type        = number
  default     = 8181
}

variable "auth_token" {
  description = "The authentication token for the Polaris API"
  type        = string
  default     = "principal:root;realm:default-realm"
  sensitive   = true
}

variable "storage_base_location" {
  description = "The base S3 location for Polaris storage"
  type        = string
  default     = "s3://polarisdemo/prod"
}

variable "s3_role_arn" {
  description = "The AWS IAM role ARN for accessing the S3 storage"
  type        = string
  default     = "arn:aws:iam::RGW947059089643XXXX:role/polaris/catalog/client"
}

variable "s3_region" {
  description = "The AWS region for the S3 storage"
  type        = string
  default     = "default"
}

variable "endpoint" {
  description = "The S3 compat endpoint"
  type        = string
  default     = "https://s3.example.com"
}

variable "profile_name" {
  description = "The AWS profile to source access / secret keys from"
  type        = string
  default     = "polaris-root"
}
