output "identities" {
  description = "engine, api and maintenance: id, principal_id (object ID) and client_id of each identity."
  value = {
    for name, identity in azurerm_user_assigned_identity.this : name => {
      id           = identity.id
      principal_id = identity.principal_id
      client_id    = identity.client_id
      name         = identity.name
    }
  }
}

output "key_vault_id" {
  description = "Resource ID of the app Key Vault."
  value       = azurerm_key_vault.app.id
}

output "key_vault_name" {
  description = "Name of the app Key Vault."
  value       = azurerm_key_vault.app.name
}

output "key_vault_uri" {
  description = "URI of the app Key Vault, for example https://kv-rdg-prod-1a2b.vault.azure.net/."
  value       = azurerm_key_vault.app.vault_uri
}
