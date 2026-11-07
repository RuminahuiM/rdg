variable "base" {
  description = "<prefix>-<env>, part of every resource name."
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
  description = "The installation's resource group."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
}

variable "engine_principal_id" {
  description = "Object ID of the engine identity."
  type        = string
}

variable "api_principal_id" {
  description = "Object ID of the api identity."
  type        = string
}
