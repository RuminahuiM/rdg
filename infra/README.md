# Infrastructure

OpenTofu configuration of one RDG installation: everything in the installation's resource
group. The resource group, the state storage and the state Key Vault come from bootstrap
stage 1; tenant-side setup (Graph permissions, Exchange role group, sign-in app, certificate)
is bootstrap stage 2. See `bootstrap/README.md` and the Infrastructure design.

| Module       | Creates                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------- |
| `core`       | identities engine, api, maintenance; app Key Vault (sign-in certificate)                    |
| `data`       | Cosmos DB (serverless, Entra only), database `rdg`, containers, data-plane roles            |
| `engine`     | Automation account, PowerShell 7.4 runtime environment, runbooks (shells), variables, schedules |
| `app`        | functions storage, Consumption plan, Function App (API), Static Web App, link, API logs     |
| `monitoring` | action group, metric alerts, budget                                                         |

Each module owns its role assignments, so the permission matrix in the Identity and Access
design maps one-to-one to code.

## Settings

One `.tfvars` file per installation; `examples/contoso.tfvars` is a full example and
`variables.tf` describes every setting. Two settings are not in the Infrastructure design's
table because they come from bootstrap stage 1: `state_key_vault_name` and
`pipeline_principal_id`. `tenant_domain` is the tenant's initial domain (Exchange needs it).

## Run it

The deploy pipeline runs it (step 6.3). By hand, signed in with `az login`:

```bash
cd infra
tofu init \
  -backend-config="resource_group_name=rg-rdg-prod-bootstrap" \
  -backend-config="storage_account_name=<printed by stage 1>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=rdg-prod.tfstate"
tofu plan -var-file=../my-settings.tfvars -out=rdg.tfplan
tofu apply rdg.tfplan
```

State and plan files are encrypted with the key in the state Key Vault (`enforced = true`), so
you need Key Vault Crypto User on that key.

## Checks

```bash
tofu fmt -recursive -check
tofu init -backend=false
tofu validate
tflint --init && tflint --recursive
tofu test -var-file=../examples/contoso.tfvars   # plans with a mocked provider, no Azure
trivy config --tf-vars ../examples/contoso.tfvars .
```

`tests/settings.tftest.hcl` plans the example settings with a mocked azurerm provider and checks
the schedules, alerts, the marker extension and the validation of bad settings.
Accepted Trivy findings are marked inline (`#trivy:ignore:<id>`) with the reason above the
resource.

## Notes

- Runbooks are created as shells that throw; the deploy step imports the built runbooks
  (`tools/Build-Runbook.ps1`) and publishes them. Their content is ignored here.
- Schedule start times and the budget start date are set once at creation and ignored after.
- Automation variables that are off (`DG_MarkerExtension`, `DG_SignInAppId` before stage 2) are
  created without a value, because Automation refuses an empty string.
- `.terraform.lock.hcl` pins azurerm 4.81.0 for linux_amd64, windows_amd64 and darwin_arm64.
  Renovate proposes provider updates.
