# Component Design: Infrastructure

Oct 9, 2026 · @Dodoe

Infrastructure covers the OpenTofu code and the bootstrap script that together create every resource. Part of Doc.

## Principles

- **OpenTofu creates Azure, people create tenant grants.** The pipeline has no Graph or Exchange rights (see Identity and Access), so everything in Entra and Exchange is done by the bootstrap scripts, run once by an admin.
- **Infrastructure and code are deployed in separate steps.** OpenTofu creates and updates resources; right after it, the same pipeline run deploys runbooks, the API package and the web app of the same version (see CI/CD).
- **One settings file per installation.** Everything an adopter may change lives in one `.tfvars` file in their own Azure DevOps repo. Organisation settings the app manages (change limit, retention, nested members) live in Cosmos DB and are changed in the web app, not here.
- **Data is never destroyed by a deployment.** Cosmos DB and both Key Vaults carry `prevent_destroy`; renames use `moved` blocks.
- **Public endpoints, Entra-only access.** No keys anywhere: Cosmos DB local auth off, storage shared keys off, Key Vault in RBAC mode. Private networking is a later version.

## Resources

All in one resource group per installation, except the bootstrap resources.

| Resource | SKU / plan | Region | Module | Notes |
| --- | --- | --- | --- | --- |
| Resource group `rg-rdg-<env>` | – | West Europe (setting; HEKS uses Switzerland North) | stage 1 | Created by bootstrap so the pipeline needs no subscription rights |
| Resource group `rg-rdg-<env>-bootstrap` | – | same | stage 1 | State storage and state key only. Pipeline can't delete it |
| Storage account (state) | Standard LRS, versioning and soft delete on | same | stage 1 | Shared keys off; container `tfstate` |
| Key Vault (state key) | Standard, RBAC, purge protection | same | stage 1 | Holds the RSA key that encrypts the state |
| User-assigned identities engine, api, maintenance | – | same | core | See Identity and Access |
| Key Vault (app) | Standard, RBAC, purge protection | same | core | Sign-in certificate only |
| Cosmos DB account | NoSQL, serverless, local auth off | same | data | Database `rdg`, containers `config`, `state`, `runs`, partition key `/pk`, TTL on |
| Automation account | Basic | same | engine | PowerShell 7.4 runtime environment with Microsoft.Graph and ExchangeOnlineManagement; three runbooks; tick schedules |
| Function App + plan | Consumption plan (Y1) on Windows | same | app | PowerShell 7.4, api identity, HTTP triggers only |
| Storage account (functions) | Standard LRS | same | app | Host storage and the packages container, identity-based connection, shared keys off; no Azure Files share (runs from a package URL) |
| Static Web App | Standard | West Europe (Static Web Apps isn't offered in Switzerland) | app | Linked to the Function App; system identity for the Key Vault reference |
| Action group + metric alerts | – | global | monitoring | Details in Monitoring and Alerting |

No Application Insights in the MVP: new instances need a Log Analytics workspace, which is out of the MVP.

## Module layout

```
infra/
  main.tf            # providers, resource group lookup, naming suffix, tags, module wiring
  variables.tf       # the settings, with defaults and validation
  outputs.tf         # names and IDs the pipeline and stage 2 need
  versions.tf        # OpenTofu and provider pins, backend, state encryption
  .terraform.lock.hcl
  .tflint.hcl
  modules/
    core/            # identities, app Key Vault
    data/            # Cosmos DB account, database, containers, SQL role assignments
    engine/          # Automation account, runtime environment, runbooks (shells), variables, schedules
    app/             # Function App, plan, host storage, Static Web App, link, API logs
    monitoring/      # action group, metric alerts, budget
  tests/             # tofu test: plans the example settings with a mocked provider
bootstrap/
  Initialize-RdgAzure.ps1   # stage 1
  Initialize-RdgTenant.ps1  # stage 2 (and -Remove)
  New-RdgTestUsers.ps1      # invented users for a test tenant
  RdgBootstrap.psm1         # helpers, tested in tests/Bootstrap
examples/
  contoso.tfvars            # a full example settings file (invented values)
```

Modules are internal, not published separately. Each owns its role assignments, so the matrix in Identity and Access maps one-to-one to code.

## Providers and versions

- **OpenTofu**: minimum 1.10 (needed for the Azure Key Vault key provider in state encryption); the pipeline installs an exact version.
- **azurerm**: pinned to one major version (`~> 4.81`; the lock file holds 4.81.0). Version 5 came out in July 2026; Renovate proposes it as its own change.
- **azapi is not needed.** azurerm 4.81 covers the Automation runtime environment and its packages, runbooks in a runtime environment and the Static Web App linked backend (`azurerm_static_web_app_function_app_registration`).
- **azuread is not used.** The pipeline has no Graph rights, so tenant objects come from the stage 2 script.
- `.terraform.lock.hcl` is committed. Renovate raises provider updates; they ship in a normal release.

## State backend and encryption

- **Backend**: `azurerm`, with `use_oidc` and `use_azuread_auth`. The Azure DevOps service connection authenticates by workload identity federation, so no storage key is used. Locking uses the blob storage's own locking.
- **One state file per installation**: `rdg-<env>.tfstate`.
- **Encryption**: OpenTofu client-side state encryption with the `azure_vault` key provider and the RSA key in the bootstrap Key Vault. The state never stores readable secrets, but it holds IDs and settings worth protecting. `enforced = true`, so an unencrypted write fails.
- **Recovery**: blob versioning and soft delete (30 days) on the state container; purge protection on the key.
- Pipeline rights: Storage Blob Data Contributor on the container, Key Vault Crypto User on the key. Nothing else in the bootstrap group.

## Settings file

One `.tfvars` per installation. Only what Azure needs to know; everything else is an app setting.

| Setting | Default | Notes |
| --- | --- | --- |
| `environment` | `prod` | Part of every name; 2 to 7 lowercase letters or digits (Key Vault names allow 24 characters) |
| `name_prefix` | `rdg` | Part of every name |
| `location` | `westeurope` | All resources except the Static Web App |
| `swa_location` | `westeurope` | Must be a Static Web Apps region |
| `tick_minutes` | `15` | 3, 5, 10, 15, 20, 30 or 60. Creates `60 / tick` hourly schedules |
| `admin_group_id`, `reader_group_id` | empty | Used by stage 2; empty means stage 2 creates the groups |
| `signin_client_id` | empty | Filled after stage 2; the sign-in stays off until set |
| `alert_email`s | required | Receives the alerts |
| `function_plan` | consumption (flex is reserved for when Microsoft lists Flex Consumption for linked backends) |  |
| `tags` | `{}` | Merged with the standard tags |
| `monthly_budget` | 50 (USD) | Budget alert on the resource group (see Monitoring and Alerting) |
| `access_mode` | read-only | read-only or read-write. Decides which tenant grants stage 2 gives and makes the engine treat everything as dry run (see Engine) |
| `tenant_domain` | required | The tenant's initial domain (contoso.onmicrosoft.com); Connect-ExchangeOnline needs it |
| `state_key_vault_name` | required | Printed by stage 1; the state encryption key lives there |
| `pipeline_principal_id` | empty | Printed by stage 1; OpenTofu gives it write access to the packages container (that container doesn't exist at stage 1) |
| `rdg_version` | 0.0.0-dev | Set by the pipeline; stamped into the rdg-version tag |

Validation blocks reject bad values at plan time (for example a tick that doesn't divide 60).

## Bootstrap

Installing runs in four steps. Both scripts are idempotent: running them again only fixes what is missing.

1. **Stage 1, Azure (person, once).** `Initialize-RdgAzure.ps1` needs Owner on the subscription. It registers the resource providers and creates both resource groups, the state storage and state Key Vault with its key, the pipeline's app registration with its federated credential (or takes an existing service principal), and the role assignments for the pipeline. It prints the values for the service connection, the backend and the settings file (`state_key_vault_name`, `pipeline_principal_id`).
2. **First pipeline run.** `tofu apply` creates everything in the Resources table. The sign-in stays off because `signin_client_id` is empty.
3. **Stage 2, tenant (person, once).** `Initialize-RdgTenant.ps1` needs the roles listed for the bootstrap admin in Identity and Access. It:
   - grants the Graph permissions to engine, api and maintenance;
   - registers the engine in Exchange Online and creates the role group "RDG Engine (\<prefix>-\<env>)" with the roles of the access mode;
   - creates the RDG sign-in app registration with its app roles, assignment required, admin consent for User.Read, the maintenance identity as owner, and the extension property `rdgDefinitionId` for groups (the marker);
   - creates the certificate in the app Key Vault (self-signed, 12 months, auto-renew) and uploads its public key;
   - assigns Admin and Reader to the configured groups, or creates the groups;
   - prints `signin_client_id`.
4. **Second pipeline run.** With `signin_client_id` set, OpenTofu turns the sign-in on. The smoke test runs.

Stage 2 also needs Key Vault Certificates Officer on the app Key Vault to create the certificate. The script assigns it to the person running it and removes it at the end.

Removing RDG: `tofu destroy` (after lifting `prevent_destroy`) and `Initialize-RdgTenant.ps1 -Remove`. Groups RDG manages stay as they are, with their last members.

## Naming and tagging

- Pattern `<type>-<prefix>-<env>`, for example `aa-rdg-prod`, `stapp-rdg-prod`; identities `id-<prefix>-<role>-<env>` (`id-rdg-engine-prod`). Bootstrap: `rg-<prefix>-<env>-bootstrap`, `st<prefix><env>bs<suffix>`, `kv-<prefix>-<env>-bs<suffix>`. Type abbreviations follow the Cloud Adoption Framework.
- Globally unique names (storage, Key Vault, Cosmos DB, Function App) get a 4-character suffix, the first 4 hex characters of the SHA-1 of the subscription ID (`cosmos-rdg-prod-1a2b`), so names stay stable across runs. OpenTofu and the bootstrap scripts compute the same value.
- Standard tags on every resource: `app = rdg`, `rdg-version`, `environment`, `managed-by = opentofu`, plus the adopter's `tags`.

## Networking

- Every endpoint is public in the MVP. A linked Function App must be publicly reachable anyway; the Static Web App is its only accepted caller.
- Cosmos DB, storage and Key Vault refuse keys, so only the identities in the matrix get in.
- Later version: private endpoints for Cosmos DB, storage and Key Vault, with the Automation account on a hybrid worker or the engine in a container. That is a larger change and is noted, not designed.

## Upgrading

- Releases are semantic versions. An adopter's repo refers to an exact RDG version; upgrading means raising that number and running the pipeline.
- The pipeline always shows `tofu plan` and stops for approval when the plan replaces or deletes anything.
- Renamed resources use `moved` blocks, never destroy and recreate. Cosmos DB and the Key Vaults also carry `prevent_destroy`.
- A release that needs a new tenant grant says so in the release notes and in a pipeline warning; the admin reruns stage 2.
- Data format changes are handled by the engine and api code (schema version in Cosmos DB), not by OpenTofu.

## Later versions

- Private endpoints and network isolation (see Networking).
- Application Insights for the api, once Log Analytics is in.
- A second, isolated test installation (best in a separate test tenant, since groups are tenant-wide).
- A proper keyless hosting model for the API. Running from a blob package to avoid the Azure Files key is a workaround (see CI/CD).

## Testing before HEKS

The first installation goes into a private test tenant, not HEKS. Same code, its own settings file, its own Azure subscription.

- **Entra ID Free is enough.** RDG evaluates rules itself, so no Premium licence is needed; that is the point of the tool.
- **One Exchange Online licence** (Exchange Online Plan 1, about CHF 4 per month) switches Exchange on in the tenant. Without it, distribution lists and mail-enabled security groups can't be tested. Cancel it after testing.
- **10 to 20 test users**, cloud-only, with values in `extensionAttribute1`–`15`, a few disabled and a few guests. `bootstrap/New-RdgTestUsers.ps1` creates them and refuses tenants with more than 100 users.
- **Azure**: a pay-as-you-go subscription in the same tenant, with a budget alert. Expected cost is the same as the estimate in the main doc, roughly USD 26–27 per month, less if the tick is raised to 60 minutes while idle.
- **Azure DevOps**: a free organisation or a project in an existing one, with a service connection to the test subscription.

HEKS is installed only after the full flow (new group, adopt, change limit, Exchange groups, certificate renewal) has run in the test tenant.

## Decisions

1. **Function App on the Consumption plan (Windows)**, not Flex Consumption. The API and main docs were updated.
2. **Stage 1 as a PowerShell script.** Stage 2 has to be PowerShell anyway (the Exchange role group can't be created in OpenTofu), so the admin needs one toolset and there is no local state file to keep safe. A script needs a bit more code for idempotency ("create if missing"), but that is a few dozen lines.
3. **Default region West Europe.** HEKS sets `switzerlandnorth` in its settings file.
4. **Test installation in a private tenant** first, as above. No separate test environment inside HEKS for the MVP.
5. **azurerm only, no azapi** (Phase 5). The provider covers every resource RDG needs.
6. **Key Vault Certificate User at vault scope** for web and maintenance. The app Key Vault holds only the sign-in certificate, and a certificate-scoped assignment can't exist before stage 2 creates the certificate.
7. **Marker extension derived in OpenTofu** from signin\_client\_id (extension\_\<app ID without dashes>\_rdgDefinitionId, empty while sign-in is off). Stage 2 registers the property on the sign-in app.
8. **Runbooks start as placeholders** that throw until the deploy step imports the built runbooks; OpenTofu ignores their content. Settings that are off (marker, sign-in app before stage 2) are Automation variables without a value, because Automation refuses empty strings.
9. **Plan tests with a mocked provider** (tofu test, infra/tests) check the example settings file, schedules, alerts and validation without Azure. Accepted Trivy findings (public endpoints, no customer-managed keys, LRS) are marked inline with the reason.
