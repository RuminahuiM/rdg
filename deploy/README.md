# Deploy

What an installation runs in its own Azure DevOps project. Every RDG release contains this folder.

| File                  | What it is                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------ |
| `azure-pipelines.yml` | The pipeline template. Copy it once into your repo next to `settings/<env>.tfvars`.         |
| `Deploy-Rdg.ps1`      | The steps the pipeline runs (Plan, Apply, DeployCode, DeployWeb, SmokeTest). Runs by hand too. |
| `RdgDeploy.psm1`      | Helpers for those steps, tested in `tests/Deploy`.                                          |

## Your repo

```
rdg-deploy/
  azure-pipelines.yml     copied from the release, rarely changes
  settings/
    prod.tfvars           the settings file (see examples/contoso.tfvars)
```

## Set up once

1. Run bootstrap stage 1 (`bootstrap/Initialize-RdgAzure.ps1`). It prints the backend values,
   the pipeline's client ID and, for the settings file, `state_key_vault_name` and
   `pipeline_principal_id`.
2. Create the service connection: Azure Resource Manager, workload identity federation (manual),
   with the issuer and subject you gave stage 1 and the client ID it printed. Scope it to the
   subscription, without granting extra roles (stage 1 already did).
3. Create the environment `rdg-<env>` (Pipelines > Environments) with these checks:
   **Approvals** (who approves an apply), **Exclusive lock**, and **Branch control** allowing
   `refs/heads/main` only.
4. Fill in the variables at the top of `azure-pipelines.yml`: `rdgVersion`, `rdgRepository`,
   `environmentName`, `settingsFile`, `serviceConnectionId` (the GUID in the service
   connection's URL), `backendResourceGroup`, `backendStorageAccount`.
5. Create the pipeline from the file and run it. The first run creates everything with sign-in
   off; then run bootstrap stage 2, put `signin_client_id` in the settings file and run again.

## What a run does

1. **Fetch**: downloads `rdg-<rdgVersion>.zip` and `SHA256SUMS` from the GitHub release and
   stops if the checksum or the bundle's `VERSION` doesn't match.
2. **Plan**: `tofu plan` with the settings file. The plan is encrypted with the state key. The
   run summary lists replaces and deletes first, and a warning appears when there are any.
3. **Approve**: the Apply stage waits for the environment's approval.
4. **Apply**: `tofu apply` of exactly that plan.
5. **Deploy code**: replaces the draft of each runbook and publishes it (the runbooks keep their
   runtime environment and schedules); uploads `api.zip` to the `packages` container and
   restarts the Function App.
6. **Web app**: fills `staticwebapp.config.json` (tenant ID, Key Vault) and uploads the web app
   with the Static Web Apps CLI. The deployment token is read through Azure Resource Manager in
   that step and never stored.
7. **Smoke test**: `/api/health` reports the new version, an anonymous call to `/api/definitions`
   is refused, and the published runbooks carry the version. Waits up to 10 minutes for a cold
   start.

Rollback: run the pipeline with the previous `rdgVersion`.

## Sign-in for OpenTofu

The AzurePowerShell task signs in Az with the service connection. For OpenTofu (backend, provider
and the state key provider) `Deploy-Rdg.ps1` sets `ARM_USE_OIDC`, `ARM_CLIENT_ID`,
`ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID`; the pipeline maps `ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID`,
`SYSTEM_ACCESSTOKEN` and `SYSTEM_OIDCREQUESTURI`, so OpenTofu requests fresh federated tokens
from Azure DevOps during long applies. Nothing is stored.

## By hand

From an unpacked bundle, signed in with `Connect-AzAccount` and `az login` (OpenTofu uses the
Azure CLI outside the pipeline), with `tofu` and Node.js on the path:

```powershell
./deploy/Deploy-Rdg.ps1 -Step Plan -SettingsFile ../rdg-deploy/settings/prod.tfvars -Environment prod `
    -BackendResourceGroup rg-rdg-prod-bootstrap -BackendStorageAccount strdgprodbs1a2b
./deploy/Deploy-Rdg.ps1 -Step Apply -Environment prod -BackendResourceGroup rg-rdg-prod-bootstrap -BackendStorageAccount strdgprodbs1a2b
./deploy/Deploy-Rdg.ps1 -Step DeployCode
./deploy/Deploy-Rdg.ps1 -Step DeployWeb
./deploy/Deploy-Rdg.ps1 -Step SmokeTest
```
