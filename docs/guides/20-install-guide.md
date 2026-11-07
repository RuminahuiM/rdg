# RDG – Install Guide

Oct 12, 2026 · @Dodoe

This guide takes you from an empty Azure subscription to RDG running with sign-in, in about two hours of work spread over two pipeline runs. It is written for the IT admin who installs RDG, and assumes a private test tenant first; production follows the same steps with its own settings file.

You end up with: one resource group with the engine (Azure Automation), the API (Function App), the web app (Static Web App), Cosmos DB and alerts; an Azure DevOps pipeline that deploys a given RDG version; and the tenant grants RDG needs, nothing more. RDG starts **read-only**: every run is a dry run until you switch it to read-write.

The order matters, because each step needs what the one before created:

1. Settings file
2. Bootstrap stage 1 (Azure)
3. Azure DevOps setup
4. First pipeline run (sign-in off)
5. Bootstrap stage 2 (tenant)
6. Second pipeline run (sign-in on)
7. Test data and first groups

## Before you start

Have these ready; the steps below assume them.

| What | Why | Notes |
| --- | --- | --- |
| Microsoft Entra tenant | Where the groups live | Entra ID Free is enough. Group-based assignment of the Admin and Reader roles needs Entra ID P1; without it you assign users one by one |
| Exchange Online | Distribution lists and mail-enabled security groups | One Exchange Online Plan 1 licence switches Exchange on in a test tenant. Without it, skip Exchange in stage 2 (`-SkipExchange`) |
| Azure subscription | All RDG resources | Pay-as-you-go is fine; expect about USD 26–27 per month. The settings file creates a budget alert |
| Azure DevOps project | The deploy pipeline | A free organisation works; you need rights to create service connections and environments |
| Your roles | Running the bootstrap scripts | Owner on the subscription (stage 1). Global Administrator, or Privileged Role + Application + Exchange Administrator (stage 2) |
| PowerShell 7.4 or later | Bootstrap scripts | Modules: Az.Accounts, Az.Resources, Az.Storage, Az.KeyVault (6.0+), Microsoft.Graph.Authentication, ExchangeOnlineManagement (3.10.1+) |
| The RDG release bundle | Scripts and example settings | Download `rdg-<version>.zip` from the RDG release page and unpack it |

Install the modules once:

```powershell
Install-Module Az.Accounts, Az.Resources, Az.Storage, Az.KeyVault, Microsoft.Graph.Authentication, ExchangeOnlineManagement -Scope CurrentUser
```

Pick two short names now; they are part of every resource name and can't change later: a **prefix** (default `rdg`, up to 6 letters or digits) and an **environment** (for example `test` or `prod`, up to 7).

## Step 1 – Settings file

Create the repo you'll use in Azure DevOps (for example `rdg-deploy`) and copy `examples/contoso.tfvars` from the bundle to `settings/<environment>.tfvars`. Every value is explained in the Settings reference below.

Fill these now:

- `environment`, `name_prefix` – the two names you picked
- `location` – region for everything except the web app (HEKS: `switzerlandnorth`)
- `swa_location` – region for the web app; Static Web Apps isn't offered in Switzerland, so `westeurope`
- `tenant_domain` – the initial domain, `<name>.onmicrosoft.com`
- `alert_emails` – who gets the alerts (a distribution list works)
- `access_mode` – leave `read-only`

Leave these empty; later steps print them:

- `state_key_vault_name`, `pipeline_principal_id` – from stage 1
- `signin_client_id`, `admin_group_id`, `reader_group_id` – from stage 2 (or set the two group IDs now if you want existing groups to get the roles)

## Step 2 – Bootstrap stage 1 (Azure)

Stage 1 creates what has to exist before the pipeline can run: both resource groups, the encrypted state storage and its key, the pipeline's identity and its roles. Run it once, as Owner of the subscription.

First start creating the Azure DevOps service connection (Project settings > Service connections > New > Azure Resource Manager > **Workload identity federation (manual)**). Azure DevOps shows an **issuer** and a **subject**; keep that page open and copy both. Then:

```powershell
Connect-AzAccount -Tenant <tenant ID>
./bootstrap/Initialize-RdgAzure.ps1 -SubscriptionId <subscription ID> -SettingsFile ./settings/test.tfvars `
    -FederationIssuer '<issuer from Azure DevOps>' `
    -FederationSubject '<subject from Azure DevOps>'
```

If Azure DevOps already created a service principal for the connection (the automatic variant), pass `-PipelinePrincipalId <its object ID>` instead of issuer and subject; stage 1 then only assigns the roles.

Add `-WhatIf` to see what it would do. The script is idempotent: rerun it after a failure and it only adds what is missing.

**No pipeline yet?** Run stage 1 with `-LocalOnly` instead of issuer and subject. It creates no app registration; you get write access to the state and use of the state key, and `pipeline_principal_id` is your own object ID. You then run the pipeline's steps by hand with `deploy/Deploy-Rdg.ps1` (Plan, Apply, DeployCode, DeployWeb, SmokeTest), signed in with `Connect-AzAccount` and `az login`.

It creates:

- `rg-<prefix>-<env>` (RDG itself) and `rg-<prefix>-<env>-bootstrap` (state)
- storage `st<prefix><env>bs<suffix>` with container `tfstate` (shared keys off, versioning, 30 days soft delete)
- Key Vault `kv-<prefix>-<env>-bs<suffix>` with the RSA key `rdg-state` that encrypts the state
- the app registration "RDG pipeline (\<prefix>-\<env>)" with the federated credential
- the pipeline's roles: Contributor and a limited RBAC Administrator on the RDG resource group, write access to `tfstate`, use of the state key

At the end it prints three blocks. Copy them:

- **Service connection**: subscription ID, tenant ID, client ID – finish the service connection with these (no extra role assignment there; stage 1 did it)
- **OpenTofu backend**: resource group and storage account – for the pipeline variables
- **Settings file**: `state_key_vault_name` and `pipeline_principal_id` – paste into your settings file

## Step 3 – Azure DevOps

Your repo holds two files; everything else comes from the RDG release on each run.

```
rdg-deploy/
  azure-pipelines.yml     copy of deploy/azure-pipelines.yml from the bundle
  settings/
    test.tfvars           your settings file
```

1. **Finish the service connection** with the subscription ID, tenant ID and client ID stage 1 printed. Name it as you like, then open it and copy its ID from the address bar (`resourceId=<GUID>`).
2. **Create the environment** `rdg-<env>` under Pipelines > Environments and add three checks: **Approvals** (who may approve an apply), **Exclusive lock**, and **Branch control** with `refs/heads/main` only.
3. **Fill the variables** at the top of `azure-pipelines.yml`:

| Variable | Value |
| --- | --- |
| `rdgVersion` | the RDG release to deploy, without the v (for example `1.0.0`) |
| `rdgRepository` | the GitHub repository that publishes RDG releases |
| `environmentName` | same as `environment` in the settings file |
| `settingsFile` | `settings/<env>.tfvars` |
| `serviceConnectionId` | the service connection's ID (GUID) |
| `backendResourceGroup` | printed by stage 1 (`rg-<prefix>-<env>-bootstrap`) |
| `backendStorageAccount` | printed by stage 1 |

4. **Commit and create the pipeline** from the existing `azure-pipelines.yml` (Pipelines > New pipeline > Azure Repos Git > Existing YAML file). The first time it uses the service connection and the environment, Azure DevOps asks you to permit that; approve both.

## Step 4 – First pipeline run

Run the pipeline on `main`. The first run creates every resource; sign-in stays off because `signin_client_id` is still empty.

1. **Plan stage.** Fetches the release, checks its checksum, and runs `tofu plan`. Open the run's **Extensions** tab (summary): on a first install it lists about 65 resources to create and nothing to replace or delete.
2. **Approve.** The Apply stage waits for the environment's approval. Read the summary, then approve. From now on, **never approve a plan with replaces or deletes you didn't expect**; the run shows a warning when there are any.
3. **Apply stage.** Creates the resources (10–20 minutes, mostly Cosmos DB and the Static Web App), publishes the runbooks, uploads the API, deploys the web app and runs the smoke test.

What to expect after the first run:

- The smoke test passes: `/api/health` reports the version and anonymous calls are refused.
- The web app's address (`https://<name>.azurestaticapps.net`) exists but sign-in doesn't work yet.
- The engine runs every 15 minutes, in read-only mode, and finds no groups to sync. Until stage 2 grants its permissions, Sync-ExchangeGroups can't connect to Exchange and may fail, so a "Sync failed" alert is possible. That is expected; stage 2 is next.

## Step 5 – Bootstrap stage 2 (tenant)

Stage 2 does everything in Entra ID and Exchange that the pipeline is deliberately not allowed to do. Run it once the first pipeline run is through, as Global Administrator (or Privileged Role + Application + Exchange Administrator), signed in to Azure with Owner on the RDG resource group.

```powershell
Connect-AzAccount -Tenant <tenant ID>
./bootstrap/Initialize-RdgTenant.ps1 -SubscriptionId <subscription ID> -SettingsFile ./settings/test.tfvars
```

Two sign-in windows follow: Microsoft Graph (consent once to the scopes it asks for) and Exchange Online. Add `-SkipExchange` if the tenant has no Exchange Online yet, and rerun without it later.

What it does, in order:

1. Grants the Graph permissions of the three managed identities. In read-only mode the engine gets read permissions only.
2. Gives the engine Exchange.ManageAsApp, registers it in Exchange Online and creates the role group "RDG Engine (\<prefix>-\<env>)".
3. Creates the app registration "RDG sign-in (\<prefix>-\<env>)": single tenant, roles Admin and Reader, assignment required, admin consent for sign-in. It also registers the marker property RDG writes on the groups it manages.
4. Creates the sign-in certificate in the app Key Vault (self-signed, 12 months, renewed automatically) and adds it to the app. You get Key Vault Certificates Officer for this step only.
5. Gives the Admin and Reader roles to `admin_group_id` and `reader_group_id`, or creates the groups "RDG Admins" and "RDG Readers".

At the end it prints three lines. Paste them into the settings file and commit:

```
signin_client_id = "..."
admin_group_id   = "..."
reader_group_id  = "..."
```

**Without Entra ID P1** the script warns that it couldn't assign the groups. Assign people directly instead: Entra admin center > Enterprise applications > RDG sign-in > Users and groups > Add, pick the user and the role.

Add yourself to "RDG Admins" (or the group you named), or you can't open the web app.

## Step 6 – Second pipeline run and first sign-in

The commit with `signin_client_id` triggers the pipeline. The plan shows a few updates (the web app's client ID setting, the weekly certificate renewal schedule and its alert, the marker variable) and nothing to replace or delete. Approve it.

Then check, in this order:

1. **Sign in.** Open the web app's address in a private browser window and sign in. You land on Groups, empty, with a read-only banner. "Access denied" means your account has no RDG role (step 5).
2. **Engine.** In the Automation account, Jobs shows Sync-EntraGroups and Sync-ExchangeGroups every 15 minutes, status Completed. The "Sync failed" alerts stop.
3. **Activity.** The Activity page shows the skipped or empty runs of the last ticks.
4. **Certificate renewal.** Start Renew-SignInCertificate once by hand in the Automation account; it ends Completed and its output says the newest key expires in about 12 months.

RDG is installed. It changes nothing in the tenant until you switch it to read-write.

## Step 7 – Test data and first groups

In a test tenant, create invented users first. Never run this in a production tenant; it refuses tenants with more than 100 users.

```powershell
./bootstrap/New-RdgTestUsers.ps1 -TenantDomain <name>.onmicrosoft.com -Count 15 -GuestCount 3
```

It creates `rdgtest01`–`rdgtest15` with department, city, job title and extension attributes (every fifth one disabled), and three guests without sending invitations. `-Remove` deletes them again.

Then, still read-only:

1. In the web app, create a group with a simple rule, for example `user.department -eq "IT"`. The preview shows the members it would get.
2. Wait for the next tick. Activity shows a dry run with the members it would add.
3. Try an adopt of an existing group and a compare against a Microsoft dynamic group, if you have one.

Stage 2 refuses write grants unless you confirm them: with `access_mode = "read-write"` it stops until you add `-AllowReadWrite`. A typo in the settings file can't give RDG write access by itself.

When the dry runs look right, switch to read-write:

1. Set `access_mode = "read-write"` in the settings file and commit; approve the run.
2. Rerun stage 2. It adds the write permissions and the Exchange write roles.
3. The next tick creates the group and adds the members. A first run that would change more members than the change limit waits for approval in the web app.

Going back works the same way: set `read-only`, run the pipeline, rerun stage 2, which removes the write grants.

## Upgrading, rolling back and removing RDG

**Upgrade.** Read the release notes first: they say whether stage 2 must be rerun and whether the settings file needs new values. Then change `rdgVersion` in `azure-pipelines.yml` in a pull request, merge, check the plan summary and approve. If the notes ask for it, rerun stage 2 from the new bundle after the run.

**Roll back.** Set `rdgVersion` to the previous version and run the pipeline. Data stays: every version can read the data of the version after it.

**Remove.** One command, signed in to Azure as Owner of the subscription and with the same tenant roles as stage 2:

```powershell
./bootstrap/Uninstall-Rdg.ps1 -SubscriptionId <subscription ID> -SettingsFile ./settings/test.tfvars -WhatIf   # shows the plan
./bootstrap/Uninstall-Rdg.ps1 -SubscriptionId <subscription ID> -SettingsFile ./settings/test.tfvars
```

It asks before each step (`-Force` doesn't ask):

1. **Tenant**: takes the Graph and Exchange grants away, removes the Exchange role group and the engine's registration, deletes the sign-in app. `-SkipTenant` leaves the tenant alone; `-SkipExchange` if there is no Exchange.
2. **RDG resources**: deletes the budget and the resource group `rg-<prefix>-<env>` with everything in it.
3. **State**: deletes `rg-<prefix>-<env>-bootstrap` (`-KeepBootstrap` keeps it).
4. **Pipeline app**: deletes the app registration stage 1 created (`-KeepPipelineApp` keeps it).

What stays, and the script lists it at the end:

- Both Key Vaults, soft-deleted for 90 days because of purge protection. A reinstall with the same prefix and environment recovers them (stage 1 and OpenTofu both do), certificate included.
- "RDG Admins" and "RDG Readers", and every group RDG managed, with its last members.
- In Azure DevOps: the service connection, the environment and the pipeline; delete them there.

## Settings reference

The settings file holds only what Azure needs to know. Organisation settings such as the change limit, audit retention or pausing are changed in the web app, not here. A wrong value is refused at plan time with a message naming the setting.

| Setting | Default | Allowed | Effect and when to change |
| --- | --- | --- | --- |
| `environment` | `prod` | 2–7 lowercase letters or digits | Part of every resource name. Never change after install |
| `name_prefix` | `rdg` | 2–6, starting with a letter | Part of every resource name. Never change after install |
| `location` | `westeurope` | an Azure region | Region of everything except the web app. Never change after install |
| `swa_location` | `westeurope` | westeurope, westus2, centralus, eastus2, eastasia | Region of the web app (Static Web Apps regions only) |
| `tenant_domain` | required | `<name>.onmicrosoft.com` | The tenant's initial domain; the engine needs it for Exchange |
| `access_mode` | `read-only` | read-only, read-write | read-only: every run is a dry run and stage 2 grants read rights only. Rerun stage 2 after a change |
| `tick_minutes` | `15` | 3, 5, 10, 15, 20, 30, 60 | How often the engine runs. Shorter = changes appear sooner and Automation costs more |
| `alert_emails` | required | one or more addresses | Receives alerts and budget notifications |
| `monthly_budget` | `50` | 1 or more (USD) | Budget on the resource group; mails at 80 % actual and 100 % forecast |
| `function_plan` | `consumption` | consumption | Hosting plan of the API; only Consumption for now |
| `tags` | `{}` | map of strings | Extra tags on every resource, added to app, rdg-version, environment, managed-by |
| `state_key_vault_name` | required | printed by stage 1 | Key Vault with the state encryption key |
| `pipeline_principal_id` | empty | printed by stage 1 | Gives the pipeline write access to the API package container. Empty = the API can't be deployed |
| `signin_client_id` | empty | printed by stage 2 | Turns sign-in, certificate renewal and the group marker on |
| `admin_group_id` | empty | group object ID | Group that gets the Admin role in stage 2. Empty = stage 2 creates "RDG Admins" |
| `reader_group_id` | empty | group object ID | Group that gets the Reader role. Empty = stage 2 creates "RDG Readers" |
| `rdg_version` | set by the pipeline | – | Don't set it; the pipeline stamps the deployed version into the tags |
| `state_key_name` | `rdg-state` | – | Name of the state key; only change if stage 1 used another name |
| `alert_guide_url` | empty | an https address | Where the Alert Guide is published. Each alert email then links to its section (\<url>#sync-failed and so on); empty = the email names the section |

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Plan fails with `AADSTS700213` or "no matching federated identity" | Issuer or subject of the service connection differ from what stage 1 registered | Rerun stage 1 with the values Azure DevOps shows now; it adds the credential |
| Plan fails reading state: 403 on the storage account or the key | Role assignments from stage 1 not active yet, or the wrong service connection | Wait 10 minutes and rerun; check `serviceConnectionId` |
| Plan says a required variable is missing | `state_key_vault_name` or `tenant_domain` empty | Fill them from stage 1 and your tenant |
| Apply fails on a role assignment with "does not have authorization" | The pipeline's limited RBAC Administrator doesn't allow that role | Rerun stage 1 from the bundle of the version you deploy |
| Apply fails: Key Vault or storage name already exists | A soft-deleted vault from an earlier install, or the name is taken | Recover or purge the old vault, or pick another prefix |
| Deploy code fails uploading `api.zip` (403) | `pipeline_principal_id` empty or wrong | Set it from stage 1 and rerun |
| Smoke test: health shows the old version | The Function App hasn't picked up the package yet | Rerun the Apply stage; check the Function App is running |
| Web app shows "Access denied" | Your account has no RDG role | Add yourself to the Admin group, or assign the role directly (step 5) |
| Sign-in error page from Static Web Apps | `signin_client_id` empty, certificate missing, or the redirect URI is wrong | Rerun stage 2, then the pipeline |
| Stage 2: "identity ... doesn't exist" | The first pipeline run didn't finish | Run the pipeline first |
| Stage 2 warns about assigning a group | No Entra ID P1 | Assign users directly (step 5) |
| Sync-ExchangeGroups fails to connect | Stage 2 ran with `-SkipExchange`, or no Exchange Online licence | Rerun stage 2 without `-SkipExchange` |

For alerts after the install, see the Alert Guide.
