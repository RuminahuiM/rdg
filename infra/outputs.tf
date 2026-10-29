# Values the deploy step and bootstrap stage 2 need. None is a secret.

output "resource_group_name" {
  description = "The installation's resource group."
  value       = data.azurerm_resource_group.main.name
}

output "identities" {
  description = "Client and object IDs of the engine, api and maintenance identities (stage 2 grants Graph and Exchange permissions to them)."
  value = {
    for name, identity in module.core.identities : name => {
      client_id    = identity.client_id
      principal_id = identity.principal_id
    }
  }
}

output "key_vault_name" {
  description = "App Key Vault; stage 2 creates the sign-in certificate here."
  value       = module.core.key_vault_name
}

output "sign_in_certificate_name" {
  description = "Name of the sign-in certificate in the app Key Vault."
  value       = local.sign_in_certificate_name
}

output "automation_account_name" {
  description = "Automation account the deploy step imports the runbooks into."
  value       = module.engine.automation_account_name
}

output "runtime_environment_name" {
  description = "Runtime environment of the runbooks."
  value       = module.engine.runtime_environment_name
}

output "function_app_name" {
  description = "Function App of the API."
  value       = module.app.function_app_name
}

output "storage_account_name" {
  description = "Storage account with the packages container (the deploy step uploads api.zip)."
  value       = module.app.storage_account_name
}

output "static_web_app_name" {
  description = "Static Web App of the web app (the deploy step fetches its deployment token)."
  value       = module.app.static_web_app_name
}

output "web_url" {
  description = "URL of the web app; stage 2 registers <url>/.auth/login/aad/callback as redirect URI."
  value       = module.app.web_url
}

output "cosmos_endpoint" {
  description = "Cosmos DB endpoint."
  value       = module.data.endpoint
}

output "marker_extension" {
  description = "Extension property that marks RDG groups (empty until signin_client_id is set)."
  value       = local.marker_extension
}

output "schedules" {
  description = "Tick schedules and the runbooks linked to each, and whether certificate renewal is scheduled."
  value = {
    ticks   = module.engine.tick_schedules
    renewal = module.engine.renewal_scheduled
  }
}

output "action_group_id" {
  description = "Resource ID of the email action group; the smoke test reads its receivers."
  value       = module.monitoring.action_group_id
}

output "alert_names" {
  description = "Names of the metric alerts."
  value       = module.monitoring.alert_names
}
