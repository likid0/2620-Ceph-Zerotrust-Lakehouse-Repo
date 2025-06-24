terraform {
  required_providers {
    polaris = {
      source  = "apache/polaris"
      version = ">= 0.1.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3.0"
    }
  }
  required_version = ">= 0.14.0"
}

provider "polaris" {
  host   = var.polaris_host
  scheme = var.polaris_scheme
  port   = var.polaris_port
  token  = var.auth_token
}

# ──────────────────────────────────────────────────────────────────────────────
# Catalog & Namespace
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_catalog" "prod" {
  name = "prod"
  type = "INTERNAL"
  properties = {
    "default-base-location" = var.storage_base_location
  }
  storage_config {
    storage_type     = "S3_COMPATIBLE"
    allowed_locations = [var.storage_base_location]
    s3_compatible_config {
      role_arn     = var.s3_role_arn
      region       = var.s3_region
      profile_name = var.profile_name
      endpoint     = var.endpoint
    }
  }
}

resource "polaris_namespace" "prod_ns" {
  catalog_name   = polaris_catalog.prod.name
  namespace_path = ["prod_ns"]
  properties = {
    description = "Production namespace"
    owner       = "data-engineering-team"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Principals & Principal Roles
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_principal" "alice" {
  name                         = "Alice"
  properties                   = { description = "EU data engineer" }
  credential_rotation_required = false
}
output "alice_secret" {
  value     = polaris_principal.alice.secret
  sensitive = true
}

resource "polaris_principal" "bob" {
  name                         = "Bob"
  properties                   = { description = "US data engineer" }
  credential_rotation_required = false
}
output "bob_secret" {
  value     = polaris_principal.bob.secret
  sensitive = true
}

resource "polaris_principal" "charlie" {
  name                         = "Charlie"
  properties                   = { description = "Service administrator" }
  credential_rotation_required = false
}
output "charlie_secret" {
  value     = polaris_principal.charlie.secret
  sensitive = true
}

resource "polaris_principal_role" "eu_data_eng" {
  name       = "eu_data_eng"
  properties = { description = "EU Data Engineering team role" }
}
resource "polaris_principal_role" "us_data_eng" {
  name       = "us_data_eng"
  properties = { description = "US Data Engineering team role" }
}

# assign principals to their roles
resource "polaris_principal_role_assignment" "alice_to_eu_data_eng" {
  principal_name      = polaris_principal.alice.name
  principal_role_name = polaris_principal_role.eu_data_eng.name
}
resource "polaris_principal_role_assignment" "bob_to_us_data_eng" {
  principal_name      = polaris_principal.bob.name
  principal_role_name = polaris_principal_role.us_data_eng.name
}
resource "polaris_principal_role_assignment" "charlie_to_service_admin" {
  principal_name      = polaris_principal.charlie.name
  principal_role_name = "service_admin"
}

# ──────────────────────────────────────────────────────────────────────────────
# Catalog Roles
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_catalog_role" "eu_data_admin" {
  catalog_name = polaris_catalog.prod.name
  name         = "eu_data_admin"
  properties   = { description = "EU Data Admin for prod" }
}
resource "polaris_catalog_role" "us_data_admin" {
  catalog_name = polaris_catalog.prod.name
  name         = "us_data_admin"
  properties   = { description = "US Data Admin for prod" }
}

# New: catalog_reader role for read-all
resource "polaris_catalog_role" "catalog_reader" {
  catalog_name = polaris_catalog.prod.name
  name         = "catalog_reader"
  properties   = { description = "Read-only access to all tables in prod_ns" }
}

# New: catalog_writer role for write-specific
resource "polaris_catalog_role" "catalog_writer" {
  catalog_name = polaris_catalog.prod.name
  name         = "catalog_writer"
  properties   = { description = "Write access on selected tables in prod_ns" }
}

# bind principal_roles to catalog_roles
resource "polaris_catalog_role_assignment" "eu_data_eng_to_eu_data_admin" {
  principal_role_name = polaris_principal_role.eu_data_eng.name
  catalog_name        = polaris_catalog.prod.name
  catalog_role_name   = polaris_catalog_role.eu_data_admin.name
}
resource "polaris_catalog_role_assignment" "us_data_eng_to_us_data_admin" {
  principal_role_name = polaris_principal_role.us_data_eng.name
  catalog_name        = polaris_catalog.prod.name
  catalog_role_name   = polaris_catalog_role.us_data_admin.name
}
resource "polaris_catalog_role_assignment" "service_admin_to_catalog_admin" {
  principal_role_name = "service_admin"
  catalog_name        = polaris_catalog.prod.name
  catalog_role_name   = "catalog_admin"
}
# New assignment: service_admin → reader
resource "polaris_catalog_role_assignment" "service_admin_to_catalog_reader" {
  principal_role_name = "service_admin"
  catalog_name        = polaris_catalog.prod.name
  catalog_role_name   = polaris_catalog_role.catalog_reader.name
}
# Existing or updated assignment: service_admin → writer
resource "polaris_catalog_role_assignment" "service_admin_to_catalog_writer" {
  principal_role_name = "service_admin"
  catalog_name        = polaris_catalog.prod.name
  catalog_role_name   = polaris_catalog_role.catalog_writer.name
}

# ──────────────────────────────────────────────────────────────────────────────
# Privilege Packages
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_privilege_package" "table_reader" {
  name       = "TABLE_READER"
  description = "Basic table read access"
  privileges = [
    "TABLE_READ_PROPERTIES",
    "TABLE_READ_DATA"
  ]
}
resource "polaris_privilege_package" "table_writer" {
  name        = "TABLE_WRITER"
  description = "Table read and write access"
  privileges  = [
    "TABLE_READ_DATA",
    "TABLE_WRITE_DATA"
  ]
}
resource "polaris_privilege_package" "table_owner" {
  name        = "TABLE_OWNER"
  description = "Full table ownership"
  privileges  = [
    "TABLE_FULL_METADATA",
    "TABLE_READ_DATA",
    "TABLE_WRITE_DATA"
  ]
}
resource "polaris_privilege_package" "principal_admin" {
  name        = "PRINCIPAL_ADMIN"
  description = "Ability to rotate any principal’s credentials"
  privileges  = ["PRINCIPAL_ROTATE_CREDENTIALS"]
}

# ──────────────────────────────────────────────────────────────────────────────
# Iceberg Tables
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_table" "products" {
  depends_on    = [polaris_namespace.prod_ns]
  catalog_name  = polaris_catalog.prod.name
  namespace_path = ["prod_ns"]
  name          = "products"
  schema {
    type = "struct"
    fields {
      id       = 1
      name     = "product_id"
      type     = "long"
      required = true
    }
    fields {
      id       = 2
      name     = "product_name"
      type     = "string"
      required = true
    }
    fields {
      id       = 3
      name     = "description"
      type     = "string"
      required = false
    }
    fields {
      id       = 4
      name     = "price"
      type     = "decimal(10,2)"
      required = true
    }
    fields {
      id       = 5
      name     = "category"
      type     = "string"
      required = false
    }
    fields {
      id       = 6
      name     = "created_at"
      type     = "timestamp"
      required = true
    }
    fields {
      id       = 7
      name     = "updated_at"
      type     = "timestamp"
      required = false
    }
  }
  properties = {
    "write.format.default"            = "parquet"
    "write.parquet.compression-codec" = "snappy"
  }
}

resource "polaris_table" "eu_users" {
  depends_on = [polaris_namespace.prod_ns]
  catalog_name   = polaris_catalog.prod.name
  namespace_path = ["prod_ns"]
  name           = "eu_user"  # Using the exact name from the SQL

  schema {
    type = "struct"
    fields {
      id       = 1
      name     = "user_id"
      type     = "long"
      required = true
    }
    fields {
      id       = 2
      name     = "username"
      type     = "string"
      required = true
    }
    fields {
      id       = 3
      name     = "email"
      type     = "string"
      required = true
    }
    fields {
      id       = 4
      name     = "country"
      type     = "string"
      required = true
    }
    fields {
      id       = 5
      name     = "registration_date"
      type     = "timestamp"
      required = true
    }
    fields {
      id       = 6
      name     = "last_login"
      type     = "timestamp"
      required = false
    }
  }

  properties = {
    "write.format.default" = "parquet"
    "write.parquet.compression-codec" = "snappy"
  }
}

resource "polaris_table" "us_users" {
  depends_on = [polaris_namespace.prod_ns]
  catalog_name   = polaris_catalog.prod.name
  namespace_path = ["prod_ns"]
  name           = "us_user"  # Using the exact name from the SQL

  schema {
    type = "struct"
    fields {
      id       = 1
      name     = "user_id"
      type     = "long"
      required = true
    }
    fields {
      id       = 2
      name     = "username"
      type     = "string"
      required = true
    }
    fields {
      id       = 3
      name     = "email"
      type     = "string"
      required = true
    }
    fields {
      id       = 4
      name     = "state"
      type     = "string"
      required = true
    }
    fields {
      id       = 5
      name     = "registration_date"
      type     = "timestamp"
      required = true
    }
    fields {
      id       = 6
      name     = "last_login"
      type     = "timestamp"
      required = false
    }
  }

  properties = {
    "write.format.default" = "parquet"
    "write.parquet.compression-codec" = "snappy"
  }
}


# ──────────────────────────────────────────────────────────────────────────────
# Grant Packages to Catalog Roles
# ──────────────────────────────────────────────────────────────────────────────
# EU data admin grants
resource "polaris_grant_package" "eu_data_admin_eu_users" {
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.eu_data_admin.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.eu_users.name
  privilege_package = polaris_privilege_package.table_writer.name
  depends_on        = [polaris_table.eu_users]
}
resource "polaris_grant_package" "eu_data_admin_products" {
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.eu_data_admin.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.products.name
  privilege_package = polaris_privilege_package.table_reader.name
  depends_on        = [polaris_table.products]
}

# US data admin grants
resource "polaris_grant_package" "us_data_admin_us_users" {
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.us_data_admin.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.us_users.name
  privilege_package = polaris_privilege_package.table_writer.name
  depends_on        = [polaris_table.us_users]
}
resource "polaris_grant_package" "us_data_admin_products" {
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.us_data_admin.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.products.name
  privilege_package = polaris_privilege_package.table_reader.name
  depends_on        = [polaris_table.products]
}

# New: catalog_reader namespace-level read
resource "polaris_grant_package" "catalog_reader_prod_ns" {
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.catalog_reader.name
  type              = "namespace"
  namespace         = ["prod_ns"]
  privilege_package = polaris_privilege_package.table_reader.name
  depends_on        = [polaris_namespace.prod_ns]
}

# New: catalog_writer table-level write (for products)
resource "polaris_grant_package" "catalog_writer_products" {
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.catalog_writer.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.products.name
  privilege_package = polaris_privilege_package.table_writer.name
  depends_on        = [polaris_table.products]
}

# ──────────────────────────────────────────────────────────────────────────────
# External data blocks (token minting)
# ──────────────────────────────────────────────────────────────────────────────
data "external" "alice_token" {
  program = [
    "${path.module}/scripts/fetch_token.sh",
    polaris_principal.alice.name,
    polaris_principal.alice.secret,
    "PRINCIPAL_ROLE:${polaris_principal_role.eu_data_eng.name}"
  ]
  depends_on = [polaris_principal_role_assignment.alice_to_eu_data_eng]
}
output "alice_token" {
  value     = data.external.alice_token.result.access_token
  sensitive = true
}

data "external" "bob_token" {
  program = [
    "${path.module}/scripts/fetch_token.sh",
    polaris_principal.bob.name,
    polaris_principal.bob.secret,
    "PRINCIPAL_ROLE:${polaris_principal_role.us_data_eng.name}"
  ]
  depends_on = [polaris_principal_role_assignment.bob_to_us_data_eng]
}
output "bob_token" {
  value     = data.external.bob_token.result.access_token
  sensitive = true
}

data "external" "charlie_token" {
  program = [
    "${path.module}/scripts/fetch_token.sh",
    polaris_principal.charlie.name,
    polaris_principal.charlie.secret,
    "PRINCIPAL_ROLE:service_admin"
  ]
  depends_on = [polaris_principal_role_assignment.charlie_to_service_admin]
}
output "charlie_token" {
  value     = data.external.charlie_token.result.access_token
  sensitive = true
}

