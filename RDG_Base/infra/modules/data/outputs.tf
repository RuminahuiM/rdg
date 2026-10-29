output "endpoint" {
  description = "Cosmos DB endpoint without port and trailing slash, for example https://cosmos-rdg-prod-1a2b.documents.azure.com. The engine also uses it as the token audience, and Entra rejects one with :443."
  value       = trimsuffix(replace(azurerm_cosmosdb_account.this.endpoint, ":443/", "/"), "/")
}

output "database_name" {
  description = "Name of the database (rdg)."
  value       = azurerm_cosmosdb_sql_database.this.name
}

output "account_id" {
  description = "Resource ID of the Cosmos DB account."
  value       = azurerm_cosmosdb_account.this.id
}
