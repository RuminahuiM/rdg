# The settings file (.tfvars) of one installation. Only what Azure needs to know; organisation
# settings such as the change limit live in Cosmos DB and are changed in the web app.
# Reference: Infrastructure design, "Settings file". Full example: examples/contoso.tfvars.

variable "environment" {
  description = "Short environment name, part of every resource name (for example prod or test)."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z0-9]{2,7}$", var.environment))
    error_message = "environment must be 2 to 7 lowercase letters or digits (Key Vault names allow 24 characters)."
  }
}

variable "name_prefix" {
  description = "Prefix in every resource name. Must match the one used for bootstrap stage 1."
  type        = string
  default     = "rdg"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.name_prefix))
    error_message = "name_prefix must be 2 to 6 lowercase letters or digits, starting with a letter."
  }
}

variable "location" {
  description = "Azure region for every resource except the Static Web App, for example westeurope or switzerlandnorth."
  type        = string
  default     = "westeurope"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be an Azure region name in lowercase without spaces, for example westeurope."
  }
}

variable "swa_location" {
  description = "Region of the Static Web App. Static Web Apps is offered in a few regions only."
  type        = string
  default     = "westeurope"

  validation {
    condition     = contains(["westeurope", "westus2", "centralus", "eastus2", "eastasia"], var.swa_location)
    error_message = "swa_location must be one of westeurope, westus2, centralus, eastus2 or eastasia."
  }
}

variable "automation_location" {
  description = "Region of the Automation account, if it can't be location (for example when the subscription's Automation quota in that region is used up). Empty means location."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9]*$", var.automation_location))
    error_message = "automation_location must be empty or an Azure region name in lowercase without spaces, for example switzerlandwest."
  }
}

variable "tick_minutes" {
  description = "Engine tick in minutes. Creates 60 / tick hourly schedules per sync runbook."
  type        = number
  default     = 15

  validation {
    condition     = contains([3, 5, 10, 15, 20, 30, 60], var.tick_minutes)
    error_message = "tick_minutes must divide 60: 3, 5, 10, 15, 20, 30 or 60."
  }
}

variable "access_mode" {
  description = "read-only (every run is a dry run, stage 2 grants read rights only) or read-write."
  type        = string
  default     = "read-only"

  validation {
    condition     = contains(["read-only", "read-write"], var.access_mode)
    error_message = "access_mode must be read-only or read-write."
  }
}

variable "tenant_domain" {
  description = "The tenant's initial domain, for example contoso.onmicrosoft.com. Connect-ExchangeOnline needs it."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+\\.onmicrosoft\\.com$", lower(var.tenant_domain)))
    error_message = "tenant_domain must be the initial domain, for example contoso.onmicrosoft.com."
  }
}

# Read by bootstrap stage 2 from this file, not by OpenTofu.
# tflint-ignore: terraform_unused_declarations
variable "admin_group_id" {
  description = "Object ID of the Entra group that gets the RDG Admin role. Used by bootstrap stage 2; empty means stage 2 creates \"RDG Admins\"."
  type        = string
  default     = ""

  validation {
    condition     = var.admin_group_id == "" || can(regex("^[0-9a-fA-F-]{36}$", var.admin_group_id))
    error_message = "admin_group_id must be empty or a group object ID (GUID)."
  }
}

# Read by bootstrap stage 2 from this file, not by OpenTofu.
# tflint-ignore: terraform_unused_declarations
variable "reader_group_id" {
  description = "Object ID of the Entra group that gets the RDG Reader role. Used by bootstrap stage 2; empty means stage 2 creates \"RDG Readers\"."
  type        = string
  default     = ""

  validation {
    condition     = var.reader_group_id == "" || can(regex("^[0-9a-fA-F-]{36}$", var.reader_group_id))
    error_message = "reader_group_id must be empty or a group object ID (GUID)."
  }
}

variable "signin_client_id" {
  description = "Application (client) ID of the RDG sign-in app, printed by bootstrap stage 2. Sign-in and certificate renewal stay off while it is empty."
  type        = string
  default     = ""

  validation {
    condition     = var.signin_client_id == "" || can(regex("^[0-9a-fA-F-]{36}$", var.signin_client_id))
    error_message = "signin_client_id must be empty or an application ID (GUID)."
  }
}

variable "alert_emails" {
  description = "Addresses that receive the alerts. A distribution list or a Teams channel address works."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0 && alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alert_emails needs at least one valid email address."
  }
}

variable "function_plan" {
  description = "Hosting plan of the API. Only consumption for now; flex is reserved for when Flex Consumption supports linked backends."
  type        = string
  default     = "consumption"

  validation {
    condition     = contains(["consumption"], var.function_plan)
    error_message = "function_plan must be consumption."
  }
}

variable "monthly_budget" {
  description = "Monthly budget in USD for the resource group; alerts at 80 % actual and 100 % forecast."
  type        = number
  default     = 50

  validation {
    condition     = var.monthly_budget >= 1
    error_message = "monthly_budget must be at least 1."
  }
}

variable "tags" {
  description = "Extra tags, merged with the standard tags (app, rdg-version, environment, managed-by)."
  type        = map(string)
  default     = {}
}

variable "rdg_version" {
  description = "RDG release being deployed. Set by the deploy pipeline from rdgVersion; stamped into the rdg-version tag."
  type        = string
  default     = "0.0.0-dev"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+(-[0-9A-Za-z.-]+)?$", var.rdg_version))
    error_message = "rdg_version must be a semantic version such as 1.2.0 or 1.3.0-rc.1."
  }
}

variable "state_key_vault_name" {
  description = "Name of the bootstrap Key Vault holding the state encryption key (printed by bootstrap stage 1)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.state_key_vault_name))
    error_message = "state_key_vault_name must be a Key Vault name (3 to 24 letters, digits and hyphens)."
  }
}

variable "state_key_name" {
  description = "Name of the RSA key that encrypts state and plan files."
  type        = string
  default     = "rdg-state"
}

variable "pipeline_principal_id" {
  description = "Object ID of the deploy pipeline's service principal (printed by bootstrap stage 1). Gets write access to the packages container; empty skips that assignment."
  type        = string
  default     = ""

  validation {
    condition     = var.pipeline_principal_id == "" || can(regex("^[0-9a-fA-F-]{36}$", var.pipeline_principal_id))
    error_message = "pipeline_principal_id must be empty or an object ID (GUID)."
  }
}

variable "alert_guide_url" {
  description = "Address of the RDG alert guide. Every alert email links to its section (<url>#sync-failed and so on). Empty: the email names the section instead."
  type        = string
  default     = ""

  validation {
    condition     = var.alert_guide_url == "" || can(regex("^https://[^#\\s]+$", var.alert_guide_url))
    error_message = "alert_guide_url must be empty or an https address without #."
  }
}
