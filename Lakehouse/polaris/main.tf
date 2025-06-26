terraform {
  required_version = ">= 1.0"
  required_providers {
    polaris  = { source = "apache/polaris", version = ">= 0.1.0" }
    external = { source = "hashicorp/external", version = ">= 2.3.0" }
    time     = { source = "hashicorp/time",     version = ">= 0.9.0" }
  }
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
    storage_type      = "S3_COMPATIBLE"
    allowed_locations = [var.storage_base_location]

    s3_compatible_config {
      role_arn          = var.s3_role_arn
      region            = var.s3_region
      profile_name      = var.profile_name
      endpoint          = var.endpoint
      path_style_access = true
    }
  }
}

resource "polaris_namespace" "prod_ns" {
  catalog_name   = polaris_catalog.prod.name
  namespace_path = ["prod_ns"]
  properties     = { owner = "data-eng" }

  lifecycle {
    ignore_changes = [properties]
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Principals & Principal‑Roles
# ──────────────────────────────────────────────────────────────────────────────
locals {
  personas = {
    admin      = "Catalog administrator"
    engineer   = "Data engineer (ingest RAW)"
    compliance = "Compliance & PII masking"
    analyst    = "Business analyst (read GOLD)"
  }
}

resource "polaris_principal" "user" {
  for_each   = local.personas
  name       = each.key
  properties = { description = each.value }
}

resource "polaris_principal_role" "role" {
  for_each   = local.personas
  name       = "${each.key}_role"
  properties = { description = "${each.value} role" }
}

resource "polaris_principal_role_assignment" "role_bind" {
  for_each            = local.personas
  principal_name      = polaris_principal.user[each.key].name
  principal_role_name = polaris_principal_role.role[each.key].name
}

# admin also gets built‑in service_admin
resource "polaris_principal_role_assignment" "admin_builtin" {
  principal_name      = polaris_principal.user["admin"].name
  principal_role_name = "service_admin"
}

# ──────────────────────────────────────────────────────────────────────────────
# Catalog Roles
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_catalog_role" "engineer_raw_rw" {
  catalog_name = polaris_catalog.prod.name
  name         = "engineer_raw_rw"
  properties   = { description = "RW on products_raw" }
}

resource "polaris_catalog_role" "compliance_gold_rw" {
  catalog_name = polaris_catalog.prod.name
  name         = "compliance_gold_rw"
  properties   = { description = "RO on RAW, RW on GOLD" }
}

resource "polaris_catalog_role" "analyst_gold_ro" {
  catalog_name = polaris_catalog.prod.name
  name         = "analyst_gold_ro"
  properties   = { description = "RO on products_gold" }
}

resource "polaris_catalog_role_assignment" "engineer_map" {
  principal_role_name = polaris_principal_role.role["engineer"].name
  catalog_name        = polaris_catalog.prod.name
  catalog_role_name   = polaris_catalog_role.engineer_raw_rw.name
}

resource "polaris_catalog_role_assignment" "compliance_map" {
  principal_role_name = polaris_principal_role.role["compliance"].name
  catalog_name        = polaris_catalog.prod.name
  catalog_role_name   = polaris_catalog_role.compliance_gold_rw.name
}

resource "polaris_catalog_role_assignment" "analyst_map" {
  principal_role_name = polaris_principal_role.role["analyst"].name
  catalog_name        = polaris_catalog.prod.name
  catalog_role_name   = polaris_catalog_role.analyst_gold_ro.name
}

# ──────────────────────────────────────────────────────────────────────────────
# Privilege Packages
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_privilege_package" "table_reader" {
  name        = "TABLE_READER"
  description = "Basic table read access"
  privileges  = [
    "TABLE_READ_PROPERTIES",
    "LIST_TABLES",
    "TABLE_READ_DATA",
  ]
}

resource "polaris_privilege_package" "table_writer" {
  name        = "TABLE_WRITER"
  description = "Table read & write access"
  privileges  = [
    "TABLE_READ_PROPERTIES",
    "LIST_TABLES",
    "TABLE_READ_DATA",
    "TABLE_WRITE_DATA",
  ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Avoid races: pause until priv‑pkgs exist
# ──────────────────────────────────────────────────────────────────────────────
resource "time_sleep" "after_priv_pkgs" {
  depends_on      = [
    polaris_privilege_package.table_reader,
    polaris_privilege_package.table_writer,
  ]
  create_duration = "10s"
}

# ──────────────────────────────────────────────────────────────────────────────
# Iceberg Tables
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_table" "products_raw" {
  depends_on     = [polaris_namespace.prod_ns]
  catalog_name   = polaris_catalog.prod.name
  namespace_path = ["prod_ns"]
  name           = "products_raw"

  schema {
    type = "struct"

    fields {
      id       = 1
      name     = "product_id"
      type     = "string"
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
      name     = "category"
      type     = "string"
      required = true
    }
    fields {
      id       = 4
      name     = "price"
      type     = "decimal(10,2)"
      required = true
    }
    fields {
      id       = 5
      name     = "quantity"
      type     = "int"
      required = true
    }
    fields {
      id       = 6
      name     = "email"
      type     = "string"
      required = true
    }
    fields {
      id       = 7
      name     = "timestamp"
      type     = "timestamp"
      required = true
    }
  }

  properties = { "format-version" = "2" }
}

resource "polaris_table" "products_gold" {
  depends_on     = [polaris_namespace.prod_ns]
  catalog_name   = polaris_catalog.prod.name
  namespace_path = ["prod_ns"]
  name           = "products_gold"

  schema {
    type = "struct"

    fields {
      id       = 1
      name     = "product_id"
      type     = "string"
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
      name     = "category"
      type     = "string"
      required = true
    }
    fields {
      id       = 4
      name     = "total"
      type     = "decimal(12,2)"
      required = true
    }
    fields {
      id       = 5
      name     = "email_hash"
      type     = "string"
      required = true
    }
    fields {
      id       = 6
      name     = "timestamp"
      type     = "timestamp"
      required = true
    }
  }
  properties = {
    "format-version"                  = "2"
    "write.format.default"            = "parquet"
    "write.parquet.compression-codec" = "snappy"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Namespace‑level grants so LIST_TABLES works
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_grant_package" "engineer_ns_read" {
  depends_on        = [time_sleep.after_priv_pkgs]
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.engineer_raw_rw.name
  type              = "namespace"
  namespace         = ["prod_ns"]
  privilege_package = polaris_privilege_package.table_reader.name
}

resource "polaris_grant_package" "compliance_ns_read" {
  depends_on        = [time_sleep.after_priv_pkgs]
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.compliance_gold_rw.name
  type              = "namespace"
  namespace         = ["prod_ns"]
  privilege_package = polaris_privilege_package.table_reader.name
}

resource "polaris_grant_package" "analyst_ns_read" {
  depends_on        = [time_sleep.after_priv_pkgs]
  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.analyst_gold_ro.name
  type              = "namespace"
  namespace         = ["prod_ns"]
  privilege_package = polaris_privilege_package.table_reader.name
}

# ──────────────────────────────────────────────────────────────────────────────
# Table‑level grants
# ──────────────────────────────────────────────────────────────────────────────
resource "polaris_grant_package" "raw_rw_for_engineer" {
  depends_on = [
    time_sleep.after_priv_pkgs,
    polaris_table.products_raw,
  ]

  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.engineer_raw_rw.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.products_raw.name
  privilege_package = polaris_privilege_package.table_writer.name
}

resource "polaris_grant_package" "raw_ro_for_compliance" {
  depends_on = [
    time_sleep.after_priv_pkgs,
    polaris_table.products_raw,
  ]

  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.compliance_gold_rw.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.products_raw.name
  privilege_package = polaris_privilege_package.table_reader.name
}

resource "polaris_grant_package" "gold_rw_for_compliance" {
  depends_on = [
    time_sleep.after_priv_pkgs,
    polaris_table.products_gold,
  ]

  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.compliance_gold_rw.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.products_gold.name
  privilege_package = polaris_privilege_package.table_writer.name
}

resource "polaris_grant_package" "gold_ro_for_analyst" {
  depends_on = [
    time_sleep.after_priv_pkgs,
    polaris_table.products_gold,
  ]

  catalog_name      = polaris_catalog.prod.name
  role_name         = polaris_catalog_role.analyst_gold_ro.name
  type              = "table"
  namespace         = ["prod_ns"]
  table_name        = polaris_table.products_gold.name
  privilege_package = polaris_privilege_package.table_reader.name
}

# ──────────────────────────────────────────────────────────────────────────────
# Token minting
# ──────────────────────────────────────────────────────────────────────────────
data "external" "token" {
  for_each = local.personas

  program = [
    "${path.module}/scripts/fetch_token.sh",
    polaris_principal.user[each.key].name,
    polaris_principal.user[each.key].secret,
    "PRINCIPAL_ROLE:${polaris_principal_role.role[each.key].name}",
  ]

  depends_on = [
    polaris_principal_role_assignment.role_bind,
    polaris_principal_role_assignment.admin_builtin,
  ]
}

output "admin_token" {
  value     = data.external.token["admin"].result.access_token
  sensitive = true
}
output "engineer_token" {
  value     = data.external.token["engineer"].result.access_token
  sensitive = true
}
output "compliance_token" {
  value     = data.external.token["compliance"].result.access_token
  sensitive = true
}
output "analyst_token" {
  value     = data.external.token["analyst"].result.access_token
  sensitive = true
}

