# Data: Cosmos DB (serverless, Entra ID only), database rdg with the containers config, state
# and runs, and the data-plane role assignments of engine and api.
# Document shapes: schemas/cosmos. Reference: Data model design.

locals {
  database_name = "rdg"

  # default_ttl: -1 turns TTL on without a default, so only documents with their own ttl expire
  # (audit entries in config). Runs expire after 30 days.
  containers = {
    config = { default_ttl = -1 }
    state  = { default_ttl = -1 }
    runs   = { default_ttl = 2592000 }
  }

  # Built-in Cosmos DB data-plane roles.
  reader_role      = "00000000-0000-0000-0000-000000000001"
  contributor_role = "00000000-0000-0000-0000-000000000002"

  # Least privilege per container (Identity and Access design, permission matrix).
  assignments = {
    engine-config = { principal_id = var.engine_principal_id, container = "config", role = local.reader_role }
    engine-state  = { principal_id = var.engine_principal_id, container = "state", role = local.contributor_role }
    engine-runs   = { principal_id = var.engine_principal_id, container = "runs", role = local.contributor_role }
    api-config    = { principal_id = var.api_principal_id, container = "config", role = local.contributor_role }
    api-state     = { principal_id = var.api_principal_id, container = "state", role = local.reader_role }
    api-runs      = { principal_id = var.api_principal_id, container = "runs", role = local.reader_role }
  }
}

resource "azurerm_cosmosdb_account" "this" {
  name                = "cosmos-${var.base}-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  tags                = var.tags

  # Keys and resource tokens are off: only Entra tokens with data-plane roles work.
  local_authentication_enabled       = false
  access_key_metadata_writes_enabled = false
  minimal_tls_version                = "Tls12"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  backup {
    type = "Continuous"
    tier = "Continuous7Days"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_cosmosdb_sql_database" "this" {
  name                = local.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
}

resource "azurerm_cosmosdb_sql_container" "this" {
  for_each = local.containers

  name                  = each.key
  resource_group_name   = var.resource_group_name
  account_name          = azurerm_cosmosdb_account.this.name
  database_name         = azurerm_cosmosdb_sql_database.this.name
  partition_key_paths   = ["/pk"]
  partition_key_kind    = "Hash"
  partition_key_version = 2
  default_ttl           = each.value.default_ttl
}

resource "azurerm_cosmosdb_sql_role_assignment" "this" {
  for_each = local.assignments

  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = "${azurerm_cosmosdb_account.this.id}/sqlRoleDefinitions/${each.value.role}"
  principal_id        = each.value.principal_id
  scope               = "${azurerm_cosmosdb_account.this.id}/dbs/${local.database_name}/colls/${azurerm_cosmosdb_sql_container.this[each.value.container].name}"
}
