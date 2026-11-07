variable "base" {
  description = "<prefix>-<env>, part of every resource name."
  type        = string
}

variable "name_prefix" {
  description = "Prefix in every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "suffix" {
  description = "4 characters from the subscription ID for globally unique names."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "The installation's resource group (created by bootstrap stage 1)."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID for the Key Vault."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
}
