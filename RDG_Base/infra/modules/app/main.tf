# App: the API (Windows Function App on the Consumption plan, run from a package in blob
# storage) and the web app (Static Web App Standard with the API as linked backend).
# Reference: Infrastructure design, API design ("Hosting"), Web App design.

locals {
  storage_name   = "st${replace(var.base, "-", "")}${var.suffix}"
  package_blob   = "api.zip"
  sign_in_active = var.signin_client_id != ""
}

# Host storage of the Function App, the API packages and the API logs. Shared keys are off:
# the host, the package download and the deploy step all use Entra ID.
# Trivy exceptions (reviewed): a Consumption plan app reaches its storage over the public
# endpoint, so no network rules (private networking is a later version); classic storage
# logging and customer-managed keys are out of scope; LRS is enough for host data and
# packages that the pipeline can upload again.
#trivy:ignore:AZU-0012
#trivy:ignore:AZU-0057
#trivy:ignore:AZU-0060
#trivy:ignore:AZU-0058
resource "azurerm_storage_account" "functions" {
  name                     = local.storage_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  tags                     = var.tags

  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true

  infrastructure_encryption_enabled = true

  blob_properties {
    # The deploy step overwrites packages/api.zip; versions allow a rollback.
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "packages" {
  name                  = "packages"
  storage_account_id    = azurerm_storage_account.functions.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "functions" {
  storage_account_id = azurerm_storage_account.functions.id

  rule {
    name    = "api-logs-30-days"
    enabled = true

    filters {
      blob_types   = ["appendBlob", "blockBlob"]
      prefix_match = ["insights-logs-functionapplogs/"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }

  rule {
    name    = "old-packages-30-days"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["packages/"]
    }

    actions {
      version {
        delete_after_days_since_creation = 30
      }
    }
  }
}

# The api identity runs the Functions host against this storage and downloads the package.
resource "azurerm_role_assignment" "api_blob_owner" {
  scope                            = azurerm_storage_account.functions.id
  role_definition_name             = "Storage Blob Data Owner"
  principal_id                     = var.api_identity.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# The deploy pipeline uploads api.zip.
resource "azurerm_role_assignment" "pipeline_packages" {
  count = var.pipeline_principal_id != "" ? 1 : 0

  scope                = azurerm_storage_container.packages.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.pipeline_principal_id
  # No principal_type: a person deploying by hand (bootstrap stage 1 -LocalOnly) works as well.
}

resource "azurerm_service_plan" "api" {
  name                = "asp-${var.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Windows"
  sku_name            = var.function_plan_sku
  tags                = var.tags
}

resource "azurerm_windows_function_app" "api" {
  name                = "func-${var.base}-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.api.id
  tags                = var.tags

  storage_account_name          = azurerm_storage_account.functions.name
  storage_uses_managed_identity = true
  # No Azure Files content share: it needs a shared key, and run-from-package doesn't use it.
  content_share_force_disabled = true
  # AzureWebJobsDashboard needs a shared key too; the logs go to storage through diagnostics.
  builtin_logging_enabled = false

  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  key_vault_reference_identity_id                = var.api_identity.id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.api_identity.id]
  }

  site_config {
    use_32_bit_worker   = false
    ftps_state          = "Disabled"
    http2_enabled       = true
    minimum_tls_version = "1.2"

    application_stack {
      powershell_core_version = "7.4"
    }
  }

  app_settings = {
    # Host storage with the user-assigned identity (accountName is set by the provider).
    AzureWebJobsStorage__credential = "managedidentity"
    AzureWebJobsStorage__clientId   = var.api_identity.client_id

    # The deploy step uploads packages/api.zip and restarts the app; set once here.
    WEBSITE_RUN_FROM_PACKAGE                     = "${azurerm_storage_account.functions.primary_blob_endpoint}${azurerm_storage_container.packages.name}/${local.package_blob}"
    WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID = var.api_identity.id

    DG_ApiClientId         = var.api_identity.client_id
    DG_CosmosEndpoint      = var.cosmos_endpoint
    DG_CosmosDatabase      = var.cosmos_database
    DG_AccessMode          = var.access_mode
    DG_AutomationAccountId = var.automation_account_id
  }

  lifecycle {
    # The Static Web App linked backend configures the Function App's authentication.
    ignore_changes = [auth_settings_v2]
  }
}

# API logs (FunctionAppLogs) to the same storage account, kept 30 days by the policy above.
# No Application Insights (Monitoring design).
resource "azurerm_monitor_diagnostic_setting" "api" {
  name               = "api-logs"
  target_resource_id = azurerm_windows_function_app.api.id
  storage_account_id = azurerm_storage_account.functions.id

  enabled_log {
    category = "FunctionAppLogs"
  }
}

resource "azurerm_static_web_app" "web" {
  name                = "stapp-${var.base}"
  location            = var.swa_location
  resource_group_name = var.resource_group_name
  sku_tier            = "Standard"
  sku_size            = "Standard"
  tags                = var.tags

  preview_environments_enabled       = false
  configuration_file_changes_enabled = true

  identity {
    type = "SystemAssigned"
  }

  # staticwebapp.config.json reads the client ID from this setting and the certificate from
  # Key Vault with the system-assigned identity. Empty until bootstrap stage 2 ran.
  app_settings = local.sign_in_active ? { AAD_CLIENT_ID = var.signin_client_id } : {}
}

resource "azurerm_role_assignment" "web_certificate_user" {
  scope                            = var.key_vault_id
  role_definition_name             = "Key Vault Certificate User"
  principal_id                     = azurerm_static_web_app.web.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_static_web_app_function_app_registration" "api" {
  static_web_app_id = azurerm_static_web_app.web.id
  function_app_id   = azurerm_windows_function_app.api.id
}
