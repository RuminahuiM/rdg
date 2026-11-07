# Core: the three user-assigned identities and the app Key Vault.
#
# engine       runs the sync runbooks (Graph, Exchange, Cosmos DB)
# api          runs the Function App (Graph read, Cosmos DB, starts runbook jobs)
# maintenance  runs Renew-SignInCertificate (owner of the sign-in app, reads the certificate)
#
# Graph and Exchange permissions are tenant-side and granted by bootstrap stage 2.

locals {
  identities = toset(["engine", "api", "maintenance"])
}

resource "azurerm_user_assigned_identity" "this" {
  for_each = local.identities

  name                = "id-${var.name_prefix}-${each.key}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Holds only the sign-in certificate (created by bootstrap stage 2, renewed by Key Vault).
# Trivy exception (reviewed): the Static Web App and the Automation sandbox read the
# certificate over the public endpoint; access is Entra RBAC only. Private networking is a
# later version.
#trivy:ignore:AZU-0013
resource "azurerm_key_vault" "app" {
  name                = "kv-${var.base}-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  public_network_access_enabled = true

  lifecycle {
    prevent_destroy = true
  }
}

# The vault holds only the sign-in certificate, so vault scope is the certificate's scope; a
# certificate-scoped assignment can't exist before stage 2 creates the certificate.
resource "azurerm_role_assignment" "maintenance_certificate_user" {
  scope                            = azurerm_key_vault.app.id
  role_definition_name             = "Key Vault Certificate User"
  principal_id                     = azurerm_user_assigned_identity.this["maintenance"].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
