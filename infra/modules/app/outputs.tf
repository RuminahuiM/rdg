output "function_app_id" {
  description = "Resource ID of the Function App."
  value       = azurerm_windows_function_app.api.id
}

output "function_app_name" {
  description = "Name of the Function App."
  value       = azurerm_windows_function_app.api.name
}

output "storage_account_name" {
  description = "Name of the functions storage account (packages container)."
  value       = azurerm_storage_account.functions.name
}

output "static_web_app_name" {
  description = "Name of the Static Web App."
  value       = azurerm_static_web_app.web.name
}

output "web_url" {
  description = "URL of the web app."
  value       = "https://${azurerm_static_web_app.web.default_host_name}"
}

output "web_principal_id" {
  description = "Object ID of the Static Web App's system-assigned identity."
  value       = azurerm_static_web_app.web.identity[0].principal_id
}
