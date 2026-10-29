variable "base" {
  description = "<prefix>-<env>, part of every resource name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "The installation's resource group."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
}

variable "engine_identity" {
  description = "The engine identity (id, principal_id, client_id)."
  type        = object({ id = string, principal_id = string, client_id = string, name = string })
}

variable "maintenance_identity" {
  description = "The maintenance identity (id, principal_id, client_id)."
  type        = object({ id = string, principal_id = string, client_id = string, name = string })
}

variable "api_principal_id" {
  description = "Object ID of the api identity, which starts sync jobs."
  type        = string
}

variable "tick_minutes" {
  description = "Engine tick in minutes (divides 60)."
  type        = number
}

variable "access_mode" {
  description = "read-only or read-write."
  type        = string
}

variable "tenant_domain" {
  description = "Initial domain of the tenant (contoso.onmicrosoft.com)."
  type        = string
}

variable "cosmos_endpoint" {
  description = "Cosmos DB endpoint."
  type        = string
}

variable "cosmos_database" {
  description = "Cosmos DB database name."
  type        = string
}

variable "marker_extension" {
  description = "Name of the directory extension property that marks RDG groups; empty while off."
  type        = string
}

variable "key_vault_uri" {
  description = "URI of the app Key Vault holding the sign-in certificate."
  type        = string
}

variable "sign_in_certificate_name" {
  description = "Name of the sign-in certificate in the app Key Vault."
  type        = string
}

variable "signin_client_id" {
  description = "Application ID of the sign-in app; empty until bootstrap stage 2 ran (renewal schedule off)."
  type        = string
}
