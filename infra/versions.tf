# OpenTofu, provider pins, state backend and state encryption.
#
# The backend is configured at `tofu init` (storage account, container, key and resource group
# come from bootstrap stage 1, see infra/README.md). Authentication is Entra-only: the pipeline
# uses workload identity federation (ARM_USE_OIDC=true), people use `az login`.

terraform {
  # 1.10 is the first version with the azure_vault key provider for state encryption.
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }

  backend "azurerm" {
    use_azuread_auth = true
  }

  # Client-side encryption of state and plan files with the RSA key from bootstrap stage 1.
  # enforced = true: an unencrypted write fails instead of silently storing plaintext.
  encryption {
    key_provider "azure_vault" "state" {
      vault_uri      = "https://${var.state_key_vault_name}.vault.azure.net"
      vault_key_name = var.state_key_name
      key_length     = 32
    }

    method "aes_gcm" "state" {
      keys = key_provider.azure_vault.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}
