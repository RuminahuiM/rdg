# Bootstrap

One-time setup of an installation, run by a person. Installing takes four steps
(Infrastructure design, "Bootstrap"):

1. **Stage 1, Azure** – `Initialize-RdgAzure.ps1`, as Owner of the subscription.
2. **First pipeline run** – `tofu apply` creates the resources; sign-in stays off.
3. **Stage 2, tenant** – `Initialize-RdgTenant.ps1`, as Global Administrator (or Privileged
   Role + Application + Exchange Administrator) with Owner on the resource group.
4. **Second pipeline run** – with `signin_client_id` set, the sign-in turns on.

Both scripts are idempotent and support `-WhatIf`. `Uninstall-Rdg.ps1` removes an installation again (below). Helpers are in `RdgBootstrap.psm1`, tested by
`tests/Bootstrap`.

## Requirements

PowerShell 7.4 and the modules Az.Accounts, Az.Resources, Az.Storage, Az.KeyVault (6.0 or later),
Microsoft.Graph.Authentication and ExchangeOnlineManagement (3.10.1 or later).

```powershell
Install-Module Az.Accounts, Az.Resources, Az.Storage, Az.KeyVault, Microsoft.Graph.Authentication, ExchangeOnlineManagement -Scope CurrentUser
Connect-AzAccount -Tenant <tenant ID>
```

## Stage 1: Azure

```powershell
./bootstrap/Initialize-RdgAzure.ps1 -SubscriptionId <id> -SettingsFile ./rdg-prod.tfvars `
    -FederationIssuer 'https://vstoken.dev.azure.com/<organization ID>' `
    -FederationSubject 'sc://<organization>/<project>/<service connection>'
```

Issuer and subject are shown when you create the Azure DevOps service connection (Azure Resource
Manager, workload identity federation, manual). If Azure DevOps created the service principal
itself, pass `-PipelinePrincipalId <object ID>` instead and only the roles are assigned.

Creates `rg-<prefix>-<env>`, `rg-<prefix>-<env>-bootstrap` with the state storage
(`st<prefix><env>bs<suffix>`, container `tfstate`) and the state Key Vault
(`kv-<prefix>-<env>-bs<suffix>`, key `rdg-state`), the pipeline app with its federated
credential, and the pipeline's roles: Contributor and Role Based Access Control Administrator
(limited by a condition to the roles OpenTofu assigns) on the RDG resource group, Storage Blob
Data Contributor on `tfstate`, Key Vault Crypto User on the state key.

It prints the service connection values, the backend settings and `state_key_vault_name` and
`pipeline_principal_id` for the settings file.

## Stage 2: tenant

```powershell
./bootstrap/Initialize-RdgTenant.ps1 -SubscriptionId <id> -SettingsFile ./rdg-prod.tfvars
```

Signs in to Microsoft Graph and Exchange Online (you are asked to consent to the Graph scopes it
needs once). Then it

- grants the Graph application permissions of engine, api and maintenance for `access_mode`
  (read-only: the engine can't write groups),
- grants Exchange.ManageAsApp to the engine, registers it in Exchange Online and creates the role
  group `RDG Engine (<prefix>-<env>)` (read-write: Distribution Groups, Security Group Creation
  and Membership, View-Only Recipients; read-only: View-Only Recipients),
- creates the app registration `RDG sign-in (<prefix>-<env>)`: single tenant, app roles Admin and
  Reader, assignment required, admin consent for User.Read, the maintenance identity as owner and
  the extension property `rdgDefinitionId` for groups (the marker),
- creates the certificate `rdg-signin` in the app Key Vault (self-signed, 12 months, renewed by
  Key Vault 60 days before expiry) and adds it to the app,
- assigns Admin and Reader to `admin_group_id` and `reader_group_id`, or creates
  "RDG Admins" and "RDG Readers",
- prints `signin_client_id`, `admin_group_id` and `reader_group_id` for the settings file.

Rerun it after changing `access_mode`; it adds or removes the write grants. `-SkipExchange`
leaves Exchange out for a tenant without Exchange Online yet.

Assigning groups to app roles needs Microsoft Entra ID P1. Without it the script warns, and you
assign users directly under Enterprise applications > RDG sign-in > Users and groups.

`-Remove` takes the grants away, removes the Exchange role group and registration and deletes the
sign-in app. The Admin and Reader groups stay, and so do the groups RDG managed. Run it together
with `tofu destroy`.

## Test users

```powershell
./bootstrap/New-RdgTestUsers.ps1 -TenantDomain contoso.onmicrosoft.com -Count 15 -GuestCount 3
```

For a test tenant only: invented cloud-only users `rdgtest01..` with department, city, job title
and extension attributes, every fifth disabled, and guests `rdgguest01@example.com` invited
without an email. Refuses tenants with more than 100 users unless `-Force`. `-Remove` deletes
them again.

## Uninstall

```powershell
./bootstrap/Uninstall-Rdg.ps1 -SubscriptionId <id> -SettingsFile ./settings/eval.tfvars -WhatIf   # the plan
./bootstrap/Uninstall-Rdg.ps1 -SubscriptionId <id> -SettingsFile ./settings/eval.tfvars
```

Removes, asking before each step (`-Force` doesn't ask): the tenant side (`Initialize-RdgTenant.ps1
-Remove`; `-SkipTenant`, `-SkipExchange`), the budget and `rg-<prefix>-<env>` with every RDG
resource, `rg-<prefix>-<env>-bootstrap` with the state (`-KeepBootstrap`), and the pipeline's app
registration (`-KeepPipelineApp`). Deleting the resource group removes the resources OpenTofu
protects with `prevent_destroy` too; no `tofu destroy` needed.

Stays: both Key Vaults, soft-deleted for 90 days (purge protection). A reinstall with the same
prefix and environment recovers them: stage 1 recovers the state vault, OpenTofu the app vault
(certificate included). Also the Admin and Reader groups, the groups RDG managed, and the Azure
DevOps service connection and environment.

