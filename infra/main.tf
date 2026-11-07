# Root module: one RDG installation in one resource group.
#
# The resource group itself, the state storage and the state Key Vault are created by
# bootstrap stage 1 (bootstrap/Initialize-RdgAzure.ps1); this configuration only reads the
# resource group. Tenant-side setup (Graph permissions, Exchange role group, sign-in app,
# certificate) is bootstrap stage 2. Reference: Infrastructure design.

provider "azurerm" {
  # The pipeline identity holds Contributor on the resource group only, so it can't register
  # resource providers; stage 1 registers the ones RDG needs.
  resource_provider_registrations = "none"

  # Shared keys are off on the functions storage account; data-plane calls use Entra ID.
  storage_use_azuread = true

  features {
    key_vault {
      # The vault holds the sign-in certificate and has purge protection; never purge from here.
      purge_soft_delete_on_destroy               = false
      purge_soft_deleted_certificates_on_destroy = false
      recover_soft_deleted_key_vaults            = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = "rg-${var.name_prefix}-${var.environment}"
}

locals {
  # Globally unique names (Key Vault, Cosmos DB, storage, Function App) get 4 characters derived
  # from the subscription ID. bootstrap/RdgBootstrap.psm1 (Get-RdgNameSuffix) computes the same.
  suffix = substr(sha1(lower(data.azurerm_client_config.current.subscription_id)), 0, 4)

  # <prefix>-<env>, used in every resource name: <type>-<prefix>-<env>[-<suffix>]
  # (identities: id-<prefix>-<role>-<env>).
  base = "${var.name_prefix}-${var.environment}"

  tags = merge(var.tags, {
    app           = "rdg"
    "rdg-version" = var.rdg_version
    environment   = var.environment
    "managed-by"  = "opentofu"
  })

  sign_in_enabled = var.signin_client_id != ""

  # Directory extension property that marks groups RDG manages. Registered on the sign-in app
  # by bootstrap stage 2; empty (marker off) until that app exists.
  marker_extension = local.sign_in_enabled ? "extension_${replace(lower(var.signin_client_id), "-", "")}_rdgDefinitionId" : ""

  # Hosting plan SKU of the API. Flex Consumption is reserved (see function_plan).
  function_plan_sku = { consumption = "Y1" }[var.function_plan]

  # Name of the sign-in certificate in the app Key Vault (bootstrap stage 2 creates it).
  sign_in_certificate_name = "rdg-signin"
}

module "core" {
  source = "./modules/core"

  base                = local.base
  name_prefix         = var.name_prefix
  environment         = var.environment
  suffix              = local.suffix
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

module "data" {
  source = "./modules/data"

  base                = local.base
  suffix              = local.suffix
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  engine_principal_id = module.core.identities.engine.principal_id
  api_principal_id    = module.core.identities.api.principal_id
}

module "engine" {
  source = "./modules/engine"

  base                = local.base
  location            = var.automation_location != "" ? var.automation_location : var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  engine_identity      = module.core.identities.engine
  maintenance_identity = module.core.identities.maintenance
  api_principal_id     = module.core.identities.api.principal_id

  tick_minutes             = var.tick_minutes
  access_mode              = var.access_mode
  tenant_domain            = var.tenant_domain
  cosmos_endpoint          = module.data.endpoint
  cosmos_database          = module.data.database_name
  marker_extension         = local.marker_extension
  key_vault_uri            = module.core.key_vault_uri
  sign_in_certificate_name = local.sign_in_certificate_name
  signin_client_id         = var.signin_client_id
}

module "app" {
  source = "./modules/app"

  base                = local.base
  suffix              = local.suffix
  location            = var.location
  swa_location        = var.swa_location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  function_plan_sku     = local.function_plan_sku
  api_identity          = module.core.identities.api
  key_vault_id          = module.core.key_vault_id
  cosmos_endpoint       = module.data.endpoint
  cosmos_database       = module.data.database_name
  access_mode           = var.access_mode
  automation_account_id = module.engine.automation_account_id
  signin_client_id      = var.signin_client_id
  pipeline_principal_id = var.pipeline_principal_id
}

module "monitoring" {
  source = "./modules/monitoring"

  base                = local.base
  resource_group_id   = data.azurerm_resource_group.main.id
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = local.tags

  alert_emails          = var.alert_emails
  monthly_budget        = var.monthly_budget
  automation_account_id = module.engine.automation_account_id
  function_app_id       = module.app.function_app_id
  sync_runbooks         = module.engine.sync_runbook_names
  renewal_enabled       = local.sign_in_enabled
  alert_guide_url       = var.alert_guide_url
}
