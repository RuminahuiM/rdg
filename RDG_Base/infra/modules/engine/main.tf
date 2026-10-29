# Engine: the Automation account, its PowerShell 7.4 runtime environment, the runbooks, the
# settings as Automation variables, and the schedules. Reference: Runbooks design.
#
# Runbooks are created here as shells with placeholder content. The deploy step imports the
# built runbooks (tools/Build-Runbook.ps1) and publishes them, so content is ignored here.

locals {
  runtime_environment = "PowerShell-7.4-RDG"

  # Modules the runbooks import. DgEngine itself is inlined into each runbook.
  # Exchange Online Management 3.10.1 or later is required from March 2027.
  packages = {
    # renovate: datasource=nuget registryUrl=https://www.powershellgallery.com/api/v2 depName=Microsoft.Graph.Authentication
    "Microsoft.Graph.Authentication" = "2.40.0"
    # renovate: datasource=nuget registryUrl=https://www.powershellgallery.com/api/v2 depName=ExchangeOnlineManagement
    "ExchangeOnlineManagement" = "3.10.1"
  }

  sync_runbooks = {
    "Sync-EntraGroups"    = "Syncs the RDG definitions of Security and Microsoft 365 groups (Microsoft Graph)."
    "Sync-ExchangeGroups" = "Syncs the RDG definitions of distribution lists and mail-enabled security groups (Exchange Online)."
  }

  runbooks = merge(local.sync_runbooks, {
    "Renew-SignInCertificate" = "Keeps the sign-in app's certificates in step with Key Vault (weekly)."
  })

  # Settings the runbooks read with Get-AutomationVariable. None is a secret.
  variables = {
    DG_EngineClientId        = var.engine_identity.client_id
    DG_TenantDomain          = var.tenant_domain
    DG_CosmosEndpoint        = var.cosmos_endpoint
    DG_CosmosDatabase        = var.cosmos_database
    DG_TickMinutes           = tostring(var.tick_minutes)
    DG_AccessMode            = var.access_mode
    DG_MarkerExtension       = var.marker_extension
    DG_MaintenanceClientId   = var.maintenance_identity.client_id
    DG_KeyVaultUri           = var.key_vault_uri
    DG_SignInCertificateName = var.sign_in_certificate_name
    DG_SignInAppId           = var.signin_client_id
  }

  # 60 / tick hourly schedules, offset by one tick each: tick-00, tick-15, tick-30, tick-45.
  tick_offsets = [for i in range(0, 60 / var.tick_minutes) : i * var.tick_minutes]

  # Start at the first full hour at least 5 minutes from now (Automation requires >= 5 minutes).
  # Only used at creation; start_time is ignored afterwards.
  first_hour = formatdate("YYYY-MM-DD'T'hh:00:00Z", timeadd(timestamp(), "65m"))

  job_schedules = {
    for pair in setproduct(keys(local.sync_runbooks), local.tick_offsets) :
    "${pair[0]}-${format("%02d", pair[1])}" => { runbook = pair[0], offset = pair[1] }
  }

  placeholder = <<-PS1
    # Placeholder created by OpenTofu. The deploy step imports the real runbook.
    throw 'This runbook has not been deployed yet. Run the RDG deploy pipeline.'
  PS1
}

resource "azurerm_automation_account" "this" {
  name                = "aa-${var.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  tags                = var.tags

  # Runbooks authenticate with the managed identities; no webhooks or hybrid workers.
  local_authentication_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [var.engine_identity.id, var.maintenance_identity.id]
  }
}

resource "azurerm_automation_runtime_environment" "this" {
  name                  = local.runtime_environment
  location              = var.location
  automation_account_id = azurerm_automation_account.this.id
  runtime_language      = "PowerShell"
  runtime_version       = "7.4"
  description           = "RDG runbooks: PowerShell 7.4 with Microsoft Graph authentication and Exchange Online."
  # Runtime environments accept at most 3 tags (400 "RuntimeEnvironmentTags ... cannot be greater
  # than 3"), and a tag change forces a replacement (destroy, recreate, re-import both packages),
  # so no rdg-version here and tags are only set at creation. The Automation account carries all tags.
  tags = { for key, value in var.tags : key => value if contains(["app", "environment"], key) }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_automation_runtime_environment_package" "this" {
  for_each = local.packages

  name                              = each.key
  automation_runtime_environment_id = azurerm_automation_runtime_environment.this.id
  content_uri                       = "https://www.powershellgallery.com/api/v2/package/${each.key}/${each.value}"
  content_version                   = each.value
}

resource "azurerm_automation_runbook" "this" {
  for_each = local.runbooks

  name                     = each.key
  location                 = var.location
  resource_group_name      = var.resource_group_name
  automation_account_name  = azurerm_automation_account.this.name
  runbook_type             = "PowerShell"
  runtime_environment_name = azurerm_automation_runtime_environment.this.name
  description              = each.value
  log_verbose              = true
  log_progress             = false
  content                  = local.placeholder
  tags                     = var.tags

  lifecycle {
    # The deploy step owns the content.
    ignore_changes = [content, publish_content_link, draft]
  }
}

resource "azurerm_automation_variable_string" "this" {
  for_each = local.variables

  name                    = each.key
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  # Automation refuses an empty string; a setting that is off (marker, sign-in app) is created
  # without a value, which Get-AutomationVariable returns as $null.
  value     = each.value != "" ? each.value : null
  encrypted = false
}

resource "azurerm_automation_schedule" "tick" {
  for_each = toset([for o in local.tick_offsets : format("%02d", o)])

  name                    = "tick-${each.key}"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Hour"
  interval                = 1
  timezone                = "Etc/UTC"
  start_time              = timeadd(local.first_hour, "${tonumber(each.key)}m")
  description             = "Engine tick at minute ${each.key} of every hour."

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "tick" {
  for_each = local.job_schedules

  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  runbook_name            = azurerm_automation_runbook.this[each.value.runbook].name
  schedule_name           = azurerm_automation_schedule.tick[format("%02d", each.value.offset)].name

  # Keys must be lowercase: Automation stores them lowercased, so "Mode" would show a change
  # on every plan. PowerShell binds the parameter case-insensitively.
  parameters = {
    mode = "Scheduled"
  }
}

# Weekly certificate renewal, only once the sign-in app exists (bootstrap stage 2).
resource "azurerm_automation_schedule" "renewal" {
  count = var.signin_client_id != "" ? 1 : 0

  name                    = "weekly-renewal"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Week"
  interval                = 1
  week_days               = ["Monday"]
  timezone                = "Etc/UTC"
  start_time              = formatdate("YYYY-MM-DD'T'03:17:00Z", timeadd(timestamp(), "24h"))
  description             = "Renew-SignInCertificate, Mondays 03:17 UTC."

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "renewal" {
  count = var.signin_client_id != "" ? 1 : 0

  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  runbook_name            = azurerm_automation_runbook.this["Renew-SignInCertificate"].name
  schedule_name           = azurerm_automation_schedule.renewal[0].name
}

# The API starts sync jobs (Sync now, approvals) and reads their status.
resource "azurerm_role_assignment" "api_job_operator" {
  scope                            = azurerm_automation_account.this.id
  role_definition_name             = "Automation Job Operator"
  principal_id                     = var.api_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "api_runbook_operator" {
  for_each = local.sync_runbooks

  scope                            = azurerm_automation_runbook.this[each.key].id
  role_definition_name             = "Automation Runbook Operator"
  principal_id                     = var.api_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
