variable "base" {
  description = "<prefix>-<env>, part of every resource name."
  type        = string
}

variable "suffix" {
  description = "4 characters from the subscription ID for globally unique names."
  type        = string
}

variable "location" {
  description = "Azure region of the Function App and its storage."
  type        = string
}

variable "swa_location" {
  description = "Region of the Static Web App."
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

variable "function_plan_sku" {
  description = "App Service plan SKU of the API (Y1 = Consumption)."
  type        = string
}

variable "api_identity" {
  description = "The api identity (id, principal_id, client_id)."
  type        = object({ id = string, principal_id = string, client_id = string, name = string })
}

variable "key_vault_id" {
  description = "Resource ID of the app Key Vault (sign-in certificate)."
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

variable "access_mode" {
  description = "read-only or read-write."
  type        = string
}

variable "automation_account_id" {
  description = "Resource ID of the Automation account the API starts jobs in."
  type        = string
}

variable "signin_client_id" {
  description = "Application ID of the sign-in app; empty until bootstrap stage 2 ran (sign-in off)."
  type        = string
}

variable "pipeline_principal_id" {
  description = "Object ID of whoever deploys the API package (the pipeline's service principal, or a person with stage 1 -LocalOnly); gets write access to the packages container. Empty: no assignment."
  type        = string
}
