# Plans the configuration with a mocked azurerm provider: no Azure access, no state backend.
# Run from infra/:  tofu init -backend=false && tofu test -var-file=../examples/contoso.tfvars
# Checks that the example settings file plans, the settings change what they should, and the
# validation blocks reject bad values.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      subscription_id = "11111111-2222-3333-4444-555555555555"
      tenant_id       = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      object_id       = "99999999-8888-7777-6666-555555555555"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod"
    }
  }

  # Computed IDs must look like real ones: the provider validates them during plan.
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-rdg-engine-prod"
      principal_id = "21111111-2222-3333-4444-555555555555"
      client_id    = "31111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.KeyVault/vaults/kv-rdg-prod-1a2b"
      vault_uri = "https://kv-rdg-prod-1a2b.vault.azure.net/"
    }
  }

  mock_resource "azurerm_cosmosdb_account" {
    defaults = {
      id       = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-rdg-prod-1a2b"
      endpoint = "https://cosmos-rdg-prod-1a2b.documents.azure.com:443/"
    }
  }

  mock_resource "azurerm_automation_account" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Automation/automationAccounts/aa-rdg-prod"
    }
  }

  mock_resource "azurerm_automation_runtime_environment" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Automation/automationAccounts/aa-rdg-prod/runtimeEnvironments/PowerShell-7.4-RDG"
    }
  }

  mock_resource "azurerm_automation_runbook" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Automation/automationAccounts/aa-rdg-prod/runbooks/Sync-EntraGroups"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id                    = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Storage/storageAccounts/strdgprod1a2b"
      primary_blob_endpoint = "https://strdgprod1a2b.blob.core.windows.net/"
    }
  }

  mock_resource "azurerm_storage_container" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Storage/storageAccounts/strdgprod1a2b/blobServices/default/containers/packages"
    }
  }

  mock_resource "azurerm_service_plan" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Web/serverFarms/asp-rdg-prod"
    }
  }

  mock_resource "azurerm_windows_function_app" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Web/sites/func-rdg-prod-1a2b"
    }
  }

  mock_resource "azurerm_static_web_app" {
    defaults = {
      id                = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Web/staticSites/stapp-rdg-prod"
      default_host_name = "proud-sea-0a1b2c3d4.azurestaticapps.net"
      identity = {
        principal_id = "41111111-2222-3333-4444-555555555555"
        tenant_id    = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      }
    }
  }

  mock_resource "azurerm_monitor_action_group" {
    defaults = {
      id = "/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Insights/actionGroups/ag-rdg-prod"
    }
  }
}

run "example_settings_plan" {
  command = plan

  assert {
    condition     = output.resource_group_name == "rg-rdg-prod"
    error_message = "The resource group name must follow rg-<prefix>-<env>."
  }

  assert {
    condition     = length(output.schedules.ticks) == 4 && alltrue([for runbooks in values(output.schedules.ticks) : runbooks == tolist(["Sync-EntraGroups", "Sync-ExchangeGroups"])])
    error_message = "tick_minutes = 15 must create 4 schedules, each linked to both sync runbooks."
  }

  assert {
    condition     = jsonencode(keys(output.schedules.ticks)) == jsonencode(["tick-00", "tick-15", "tick-30", "tick-45"])
    error_message = "Tick schedules must be offset by one tick."
  }

  assert {
    condition     = output.schedules.renewal == false && output.marker_extension == ""
    error_message = "Without signin_client_id, renewal and the marker extension stay off."
  }

  assert {
    condition     = output.alert_names == tolist(["alert-rdg-prod-api-errors", "alert-rdg-prod-job-stuck", "alert-rdg-prod-sync-failed", "alert-rdg-prod-sync-not-running"])
    error_message = "Without sign-in, the certificate renewal alert must not exist."
  }
}

run "sign_in_on_and_short_tick" {
  command = plan

  variables {
    signin_client_id = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
    tick_minutes     = 5
    access_mode      = "read-write"
  }

  assert {
    condition     = length(output.schedules.ticks) == 12
    error_message = "tick_minutes = 5 must create 12 schedules."
  }

  assert {
    condition     = output.schedules.renewal
    error_message = "With signin_client_id, the weekly renewal must be scheduled."
  }

  assert {
    condition     = output.marker_extension == "extension_0a1b2c3d4e5f60718293a4b5c6d7e8f9_rdgDefinitionId"
    error_message = "The marker extension is extension_<app ID without dashes, lowercase>_rdgDefinitionId."
  }

  assert {
    condition     = contains(output.alert_names, "alert-rdg-prod-certificate-renewal-failed")
    error_message = "With sign-in, the certificate renewal alert must exist."
  }
}

run "tick_must_divide_60" {
  command = plan

  variables {
    tick_minutes = 7
  }

  expect_failures = [var.tick_minutes]
}

run "environment_too_long" {
  command = plan

  variables {
    environment = "staging1"
  }

  expect_failures = [var.environment]
}

run "access_mode_values" {
  command = plan

  variables {
    access_mode = "readwrite"
  }

  expect_failures = [var.access_mode]
}

run "alert_emails_required" {
  command = plan

  variables {
    alert_emails = ["not-an-address"]
  }

  expect_failures = [var.alert_emails]
}

run "tenant_domain_is_initial_domain" {
  command = plan

  variables {
    tenant_domain = "contoso.org"
  }

  expect_failures = [var.tenant_domain]
}

run "swa_region" {
  command = plan

  variables {
    swa_location = "switzerlandnorth"
  }

  expect_failures = [var.swa_location]
}
