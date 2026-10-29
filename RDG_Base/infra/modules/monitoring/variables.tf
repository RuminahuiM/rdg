variable "base" {
  description = "<prefix>-<env>, part of every resource name."
  type        = string
}

variable "resource_group_id" {
  description = "Resource ID of the installation's resource group (budget scope)."
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

variable "alert_emails" {
  description = "Addresses that receive the alerts and budget notifications."
  type        = list(string)
}

variable "monthly_budget" {
  description = "Monthly budget in USD."
  type        = number
}

variable "automation_account_id" {
  description = "Resource ID of the Automation account."
  type        = string
}

variable "function_app_id" {
  description = "Resource ID of the Function App."
  type        = string
}

variable "sync_runbooks" {
  description = "Names of the sync runbooks."
  type        = list(string)
}

variable "renewal_enabled" {
  description = "Whether certificate renewal runs (the sign-in app exists)."
  type        = bool
}

variable "alert_guide_url" {
  description = "Address of the alert guide; empty names the guide's section instead of linking it."
  type        = string
}
