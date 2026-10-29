# Dynamic Groups Engine – Solution Design

Oct 6, 2026 · @Dodoe

## Overview

The engine evaluates rules on a schedule and writes the result as a static member list into any M365 group type, so the groups work wherever Microsoft dynamic groups are refused (Defender preset policies, Exchange scopes, mail-enabled groups).

Entra dynamic groups do persist their members, but they cannot be mail-enabled, cannot mix rule members with manual includes/excludes, need Entra ID P1 per member and cap rules at 3,072 characters. Exchange dynamic distribution groups are not accepted in Defender policies at all.

| Decision | Choice |
| --- | --- |
| Rule evaluation | Own engine (PowerShell module), Entra-compatible rule syntax |
| Objects in v1 | Users only (devices later) |
| Dashboard | Minimal web app: Azure Static Web App (Standard) + linked Function App as API; sign-in limited to an IT group |
| Data store | Azure Cosmos DB for NoSQL, serverless, Entra authentication only |
| Sync engine | Azure Automation: two runbooks (Entra groups via Graph, Exchange groups via EXO PowerShell), user-assigned managed identity |
| Infrastructure as code | OpenTofu + one bootstrap script for tenant grants |
| Source control and CI/CD | Azure DevOps in the adopter's own tenant; public mirror on GitHub |
| Audience | Public open source, HEKS as first user |

## Design map

&#91;embedded content: design map · 3 zones, 9 components\]

IT uses two things: the web app for group definitions and the repo for code. Azure DevOps deploys the resource group. At runtime the runbooks read definitions from Cosmos DB, read users from Entra ID, write members through Graph (Security, M365) or Exchange Online PowerShell (mail-enabled security groups, distribution lists), and write status back to Cosmos DB.

## Components to design

The tool has nine components; each gets its own design document, worked through one by one. The engine is the core: runbooks and API are thin shells around it, so rules behave the same in preview and in sync.

| # | Component | What it is | Design doc |
| --- | --- | --- | --- |
| 1 | Engine | PowerShell module: rule language, parser, evaluator, diff, safety brakes, writers for Graph and Exchange | Component Design: Engine |
| 2 | Runbooks | Sync-EntraGroups and Sync-ExchangeGroups in Azure Automation, thin shells around the engine | Component Design: Runbooks |
| 3 | API | PowerShell Function App behind the web app: CRUD, validation, preview, sync now, audit | Component Design: API |
| 4 | Web app | React + Fluent UI dashboard: Groups, Edit group, Activity, Settings, Audit | Component Design: Web App |
| 5 | Data model | Cosmos DB containers and document schemas | Doc |
| 6 | Identity and access | Managed identities, Graph and Exchange rights, sign-in for the IT group | Doc |
| 7 | Infrastructure | OpenTofu modules and the bootstrap script | Doc |
| 8 | CI/CD | Repository and Azure DevOps pipelines | Doc |
| 9 | Monitoring and alerting | Status, run records, Activity screen, metric alerts | Doc |

## Sync cadence and runbook layout

Two runbooks share one engine module and run on the same tick: Sync-EntraGroups (Security, M365 via Graph) and Sync-ExchangeGroups (mail-enabled security, distribution lists via EXO PowerShell). Each run loads all users once, evaluates every due definition in memory and writes only the differences; the Exchange runbook only connects to Exchange when one of its groups is due.

Automation schedules run at most hourly, so a tick of N minutes = 60/N hourly schedules, offset evenly. The tick is an infrastructure setting (tfvars, default 15 min); a group's Frequency below the tick is raised to the tick with a warning.

| Tick | Hourly schedules per runbook | Job minutes / month (2 runbooks) | Cost / month |
| --- | --- | --- | --- |
| 15 min (default) | 4 | \~8,600 | \~USD 16 |
| 5 min | 12 | \~25,900 | \~USD 51 |
| 3 min (minimum) | 20 | \~43,200 | \~USD 85 |

Estimate assumes 1.5 min per run and USD 0.002 per job minute after 500 free minutes; real run times get measured in step 2.

- **No 1-minute option:** Azure Automation only promises that 99.9 % of jobs start within 30 minutes; start-up and module load usually take longer than a minute. 3 min is best effort.
- **Overlap guard:** a run that finds the previous run of the same runbook still active exits and logs a skipped tick, so two jobs never write the same group.
- **Not one job per group:** each job pays start-up, reloads all users and reconnects to Exchange, so N groups cost N times as much; pay-as-you-go accounts also run at most 10 jobs at once (Enterprise/CSP 50).
- **Not one schedule per group:** schedules are hourly at minimum and would be created outside OpenTofu state.
- **Scaling later:** if a run gets too slow, the runbook takes a shard parameter (groups 1–50, 51–100 …) and each tick starts one job per shard.
- **Memory:** sandboxes have 400 MB, so the user snapshot loads only the properties that rules reference.
- **Host-agnostic engine:** if guaranteed minute-level sync is ever needed, the same module can run in Azure Functions.

## Resource list

OpenTofu owns every Azure resource. The bootstrap script only does the tenant-level grants an admin must consent to, so the pipeline identity never holds Graph or Exchange rights. Two identities split the work: "engine" writes groups, "api" only reads directory data and writes configuration.

| Resource | Lives in | Purpose | Created by |
| --- | --- | --- | --- |
| Resource group | Azure | Holds all runtime resources | OpenTofu |
| Automation Account + user-assigned identity "engine" | Azure + Entra | Runs the runbooks; the only identity that writes groups; survives a recreated account | OpenTofu |
| Runtime environment PowerShell 7.4 + modules (Microsoft.Graph.Authentication, ExchangeOnlineManagement) | Azure | PS 7.1/7.2 retire on 30 Sep 2026; REST-only, so via the azapi provider | OpenTofu (azapi) |
| Runbooks Sync-EntraGroups + Sync-ExchangeGroups + engine module | Azure | Evaluate rules, write members, write status | OpenTofu |
| 60/tick hourly schedules per runbook (default 4) | Azure | Tick cadence; Automation schedules run at most hourly | OpenTofu |
| Static Web App, Standard plan | Azure | Hosts the UI; custom Entra sign-in restricted to the tenant | OpenTofu |
| Function App (Consumption plan on Windows, PowerShell 7.4) + storage account + user-assigned identity "api" | Azure + Entra | API linked to the Static Web App; loads the engine module to validate and preview rules; starts runbook jobs for "sync now" | OpenTofu |
| Cosmos DB for NoSQL account (serverless, local auth disabled), containers config, state, runs | Azure | Configuration, current status, change history | OpenTofu |
| Cosmos DB data role assignments | Azure | one writer per container: api writes config, engine writes state and runs; each reads the other's | OpenTofu |
| Automation Job Operator role for "api" | Azure | Start runbook jobs from the UI | OpenTofu |
| Not in the MVP (later opt-in): Log Analytics workspace + Application Insights | Azure | Long-term KQL queries and API traces | OpenTofu |
| Metric alert rules on the Automation account + action group (email / Teams) | Azure | Failed or blocked runs, missing runs | OpenTofu |
| Storage account for state + Key Vault key | Azure | OpenTofu remote state, encrypted | Bootstrap stage 1 |
| App registration for sign-in (app roles Admin and Reader, assignment required, one group per role) | Entra ID | Only members of the IT group can open the app | Bootstrap stage 2 (admin) |
| Graph app roles on "engine": User.Read.All, GroupMember.ReadWrite.All, Group.Create | Entra ID | Read users, create groups, write members | Bootstrap stage 2 (admin) |
| Graph app roles on "api": User.Read.All, GroupMember.Read.All | Entra ID | People and group pickers, rule preview; read-only | Bootstrap stage 2 (admin) |
| Exchange.ManageAsApp + "engine" service principal in a custom Exchange role group (Distribution Groups role) | Exchange Online | Write mail-enabled security groups and distribution lists | Bootstrap stage 2 (admin) |
| Azure DevOps project + repo (imported from GitHub) | Azure DevOps | Code, OpenTofu, tests | Adopter |
| Service connection (Azure Resource Manager, workload identity federation) | Azure DevOps + Entra | Pipeline login without secrets; rights on the resource group, state storage and Key Vault only | Adopter |
| Pipelines ci.yml + deploy.yml | Azure DevOps | Validate on pull request; plan, approve, apply, deploy the app on main | Adopter (from repo) |
| Environment "production" with approval check | Azure DevOps | Human approval before apply | Adopter |

## Azure DevOps instead of GitHub

Yes: Azure DevOps covers repo, CI and deployment, and the runtime never depends on it. GitHub stays the public upstream where you publish releases and take contributions; each adopter imports the repo into their own Azure DevOps project.

- **Repo:** Azure Repos, imported from GitHub. Updates = pull a new release tag from upstream, then the normal pipeline runs.
- **CI (ci.yml, on pull request):** PSScriptAnalyzer, Pester tests for the parser and sync logic, `tofu fmt -check` and `tofu validate`.
- **CD (deploy.yml, on main):** `tofu plan` → approval on the "production" environment → `tofu apply`. Runbook code ships through OpenTofu (`content = file(...)`), not through Automation's built-in source control, which supports only PowerShell 5.1 runbooks.
- **Login without secrets:** an Azure Resource Manager service connection with workload identity federation. OpenTofu runs inside an AzureCLI@2 task and reuses that federated login for provider and azurerm backend.
- **Least privilege:** the pipeline identity gets Azure RBAC on the resource group, state storage and Key Vault only. Graph and Exchange grants are done once by an admin in bootstrap stage 2, so a compromised pipeline cannot grant itself tenant rights.
- **Agents:** private projects get 1 free Microsoft-hosted parallel job (1,800 min/month, 60 min per job) or 1 free self-hosted job with no time limit. A deploy takes a few minutes, so the free grant is enough.

## Updating the tool and its settings

OpenTofu updates resources in place, nobody redeploys from scratch: the state knows every resource, so `tofu plan` lists exactly what a new version changes and `apply` touches only that. List items and groups are not in OpenTofu state and are never touched by an update.

1. Upstream publishes a release tag (e.g. v1.3.0); the changelog flags "tenant changes: yes/no" and the list schema version.
2. The adopter pulls the tag into their Azure Repo (fetch upstream tags, merge into a branch, pull request); CI runs.
3. Merge to main: the deploy pipeline runs `tofu plan`, e.g. runbook content "update in-place", 8 new schedules "create".
4. Approval, then `apply`: runbook content is replaced and published. Jobs already running finish on the old version; the next tick uses the new one.
5. First run after the update: the engine migrates stored documents if the data schema version changed, then checks its token for the permissions it needs. A missing one sets LastResult = Error and alerts "rerun bootstrap stage 2".

| Change | What OpenTofu does | Impact |
| --- | --- | --- |
| Runbook or module code | Update in place | None, next tick uses it |
| Tick, e.g. 15 → 5 min (tfvars) | Creates 8 more schedules per runbook | None |
| Alert email, log retention (tfvars) | Update in place | None |
| Name prefix or region | Replace (-/+), shown in the plan before approval | Avoid; the user-assigned identity keeps its grants |
| New Graph or Exchange permission | Not OpenTofu: rerun bootstrap stage 2 | Engine reports the gap until done |

Known quirk: the azurerm provider has had issues where a runbook update recreates its schedule links. It is harmless and visible in the plan; provider versions are pinned and upgrades tested in CI.

## Adoption journey

A new organisation goes from zero to its first synced group in 8 steps, with one admin session for the tenant grants and everything else through the pipeline.

**Prerequisites:** an Azure subscription (Owner on the target resource group), an Azure DevOps organisation, Exchange Online, two Entra groups for the app's roles (admins, readers), and for one session a Global Administrator (or Privileged Role Admin + Application Admin + Exchange Admin).

1. **Get the code:** import the GitHub repo into a new Azure DevOps project.
2. **Fill one settings file** (`config/settings.tfvars`): tenant, subscription, region, name prefix, IT group, alert email.
3. **Bootstrap stage 1** (`Bootstrap.ps1 -Stage Foundation`, run locally): creates state storage and Key Vault, prints the values the pipeline needs.
4. **Wire Azure DevOps:** service connection (workload identity federation, scoped to the resource group), "production" environment with an approval, pipelines from `ci.yml` and `deploy.yml`.
5. **First deploy:** the pipeline runs OpenTofu (engine, web app, API, Cosmos DB, monitoring) and deploys the app and runbook code.
6. **Bootstrap stage 2** (`Bootstrap.ps1 -Stage Tenant`, once, by the admin): creates the sign-in app registration with the IT group assigned, grants Graph roles to "engine" and "api", adds "engine" to the Exchange role group, prints the app URL.
7. **Smoke test:** open the app, create a definition with DryRun on, check the preview, press Sync now, check the status.
8. **Go live:** switch DryRun off, then move existing rules over; Entra dynamic rule text can be pasted 1:1.

Later updates: pull a newer release tag into the repo; the pipeline shows the plan and waits for approval.

## Dashboard: the web app

The dashboard is a small web app with five screens. Only members of the IT group can sign in, and every change lands in an audit trail (who, when, before and after).

| Screen | What IT does there |
| --- | --- |
| Groups | Table of all definitions: name, type, frequency, last result, members, last sync; filter "needs attention" |
| Edit group | Name, type, target group (empty = create), rule editor with instant syntax check, include/exclude pickers, frequency, Enabled, DryRun, MaxChangePercent; Preview and Sync now buttons |
| Activity | Runs per group for the last 30 days: added and removed users, errors, link to the Automation job |
| Settings | Frequency options, defaults (DryRun, MaxChangePercent), marker attribute, preview size |
| Audit | Change history per definition |

The engine writes LastSyncUtc, LastResult (OK, Warning, Error, Blocked), MemberCount, Added, Removed, Skipped and LastError back to each definition.

**Lifecycle of one definition:**

1. IT creates it with DryRun on; the rule is checked while typing, by the same parser the engine uses (loaded in the API).
2. Preview lists the users that match now and the difference to the target group.
3. Next tick or Sync now: the engine creates the group if needed and writes status; with DryRun it only records the would-be changes.
4. DryRun off: the group syncs at its frequency.
5. Disabled: syncing stops, the group stays as it is. Deleting a definition never deletes the group; the engine reports managed groups without a definition as orphaned.

**Exchange group types** only take users with an Exchange recipient; others are counted in Skipped. Security and M365 groups take every matching user. Target groups synced from on-prem AD are refused in the MVP; supporting them is a candidate for a later version.

**Settings:** frequency options and defaults live on the Settings screen and apply on the next tick. Only infrastructure settings (tick, region, alert email) go through tfvars and the pipeline.

## Data store

Cosmos DB for NoSQL (serverless) fits best: the data is a few hundred small JSON documents, read on every tick, edited by a handful of people, and two writers must never overwrite each other.

| Option | Verdict | Reason |
| --- | --- | --- |
| Cosmos DB for NoSQL, serverless | Chosen | JSON documents match definitions (nested includes, excludes, status); ETags stop lost updates; query on any field; Entra auth only, keys disabled; pay per request, cents at this volume |
| Table Storage | Works, but cramped | Cheapest; but flat rows (lists stored as JSON strings) and efficient queries only on partition and row key |
| Azure SQL Database serverless | Overkill | Schema migrations for a handful of entity types; the engine wakes it every tick, so it never auto-pauses and the free offer runs out |
| PostgreSQL flexible server | Overkill | Always-on server with a monthly base cost, schema migrations |

Containers: config, state, runs (30-day time-to-live); details in the Data Model doc. The Cosmos DB free tier (1000 RU/s, 25 GB) does not apply to serverless accounts, which is fine at this volume.

## Hosting cost

About USD 26–27 per month at the default 15-minute tick; the web app adds about USD 10 of that, the sync engine is the larger part. List prices in USD; Switzerland North is usually a bit higher.

| Item | Per month (USD, estimate) |
| --- | --- |
| Static Web App, Standard plan | 9 |
| Function App API, Consumption plan (Windows) | \~0 (free grant: 100,000 GB-s, 250,000 executions) |
| Cosmos DB serverless | < 1 |
| Storage accounts (API, state) + Key Vault | < 1 |
| Log Analytics | 0 (not in the MVP) |
| Azure Automation, 2 runbooks, 15-min tick | \~16 |

Why not cheaper: the Free Static Web Apps plan cannot restrict sign-in to one tenant, and its built-in API cannot use a managed identity, so the API would need stored keys. Container Apps with scale to zero would be near USD 0 but adds cold starts and a container image pipeline.

## Monitoring and alerting

Debugging happens in the web app; Log Analytics is not part of the MVP. Every run writes a record per group (result, added and removed users, error, Automation job ID) to Cosmos DB, so IT sees what happened and why in the same place they edit the rule.

| Layer | What it shows | Where |
| --- | --- | --- |
| Per group | LastResult, MemberCount, Added, Removed, Skipped, LastError | Groups screen, "needs attention" filter |
| Per run | Added/removed users, error text, link to the Automation job; kept 30 days | Activity screen |
| Raw job output | Full job streams of each run, kept 30 days | Automation job history (linked from Activity) |
| Alerting | Metric alerts on the Automation account: any job with status Failed; fewer completed jobs than expected (missing runs) | Email or Teams via the action group |
| Optional | Log Analytics + Application Insights for long-term KQL queries and API traces | Not in the MVP; later an opt-in tfvars switch |

Safety brakes never fail silently: an empty rule result, a change above MaxChangePercent or a target without the engine's marker sets LastResult = Blocked, and the runbook ends as Failed so the metric alert fires. Metric alerts need no Log Analytics workspace.

## Mini project plan

Five steps, each ending in something that runs; HEKS can use the engine for the Defender case after step 3.

| Step | Scope | Done when |
| --- | --- | --- |
| 1. Rule engine | Repo structure, grammar spec, tokenizer + parser, evaluator incl. memberOf (existing groups and other definitions, cycle detection), Pester tests; local only, no Azure | Sample rules (incl. the EOP rule) give the expected users against a fixture user set |
| 2. Sync core | Graph writer (Security) and EXO writer (mail-enabled security) behind the two runbook entry points, marker check, safety brakes, DryRun; config from a local JSON file | Run from a workstation keeps one test MESG in sync in a test tenant |
| 3. Web app | Cosmos DB model, API (CRUD, validation, preview, sync now), four screens, sign-in for the IT group, audit trail; engine reads config from Cosmos DB | A definition created in the app syncs on the next local run |
| 4. Azure deployment | OpenTofu modules, bootstrap stages 1 + 2, ci.yml and deploy.yml, metric alerts | A fresh resource group deploys from the pipeline; HEKS EOP Strict group runs in Azure |
| 5. v1.0 release | M365 and distribution list types, include/exclude, Exchange role group scope, README + adoption guide, GitHub release | A second person deploys it from the docs alone |

Later: device groups, target groups synced from on-prem AD, opt-in Log Analytics + Application Insights, sharding for large tenants, a Container Apps hosting option for lower cost.

## Additions after component design

In the MVP:

- **Read-only mode** (`access_mode`): an installation that can only read the tenant, enforced by permissions. HEKS is first installed read-only to test against real users, then switched to read-write. Details in Engine and Identity and Access.
- **Compare group**: a definition can name an existing group, typically the Microsoft dynamic group it replaces, and every run lists the differences. A small addition: one field, one extra Graph call, one card in the web app.
- **Migrating Microsoft dynamic groups**: adopt one, the rule is pre-filled, and on approval the engine switches it to assigned membership and takes over. Same group ID, mail address and policy references.
- **Scale at HEKS**: about 2,000 users, about 800 in scope, a modest number of groups. Well within one run per tick.

Test order: private tenant (writes, Exchange groups, migration) → HEKS read-only with compare groups → HEKS read-write.

Noted for later:

- **Before first public launch:** a data-protection section (names and UPNs in run and audit records, retention, region).
- **Later:** open-source basics (licence, README, SECURITY.md, contribution guide). Development starts in a private GitHub repo.
- **Way later:** README note that Microsoft retires the memberOf operator in dynamic groups (affected groups stop updating after 3 November 2026), while RDG keeps supporting it.

## Open questions

- [x] Group references: one syntax, `user.memberof -any (group.objectId -in ['id'])`. For a group this tool manages, the engine evaluates that group's definition in the same run and uses the fresh result, never its last synced members; for any other group it reads the current members. Cycles between managed groups are rejected. Microsoft ends its own memberOf preview on 3 Nov 2026.
- [x] Exchange permissions: a custom Exchange role group, not RBAC for Applications (mailbox data only).
- [x] On-prem AD groups are out of scope; Exchange group types only take users with an Exchange recipient.
- [x] Dashboard: minimal web app instead of a SharePoint list, with Sync now; no Logic Apps anywhere.
- [x] Only the IT group can sign in.
- [ ] Static Web Apps custom sign-in expects a client secret in app settings: Key Vault reference plus a rotation plan, or a secretless option? Verify in step 3.
- [ ] Does a management scope on a marker attribute still allow creating new Exchange groups? Test in step 2.
- [ ] Project name.

## Sources

- [Preset security policies (supported group types)](https://learn.microsoft.com/en-us/defender-office-365/preset-security-policies)
- [Azure Automation schedules (hourly minimum, 15-min workaround)](https://learn.microsoft.com/en-us/azure/automation/shared-resources/schedules)
- [Azure Automation limits (concurrent jobs, 400 MB, 500 free minutes)](https://learn.microsoft.com/en-us/azure/automation/automation-subscription-limits-faq)
- [Runbook start SLA (30 minutes)](https://learn.microsoft.com/en-us/troubleshoot/azure/automation/runbooks/job-not-start-as-expected)
- [Azure Automation cost per job minute (USD 0.002)](https://www.kelverion.com/blog/azure-automation-costs-explained)
- [Azure Automation runtime environments](https://learn.microsoft.com/en-us/azure/automation/runtime-environment-overview)
- [Azure Automation source control (PS 5.1 only)](https://learn.microsoft.com/en-us/azure/automation/source-control-integration)
- [Exchange Online app-only auth (Entra roles, custom role groups)](https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2)
- [RBAC for Applications in Exchange Online (mailbox data only)](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
- [Selected permissions in SharePoint (Sites.Selected roles)](https://learn.microsoft.com/en-us/graph/permissions-selected-overview)
- [azurerm runbook update recreates job schedules (issue #8634)](https://github.com/hashicorp/terraform-provider-azurerm/issues/8634)
- [Azure DevOps parallel jobs and free grant](https://learn.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs?view=azure-devops)
- [OpenTofu azurerm backend](https://opentofu.org/docs/language/settings/backends/azurerm/)
- [Graph advanced queries (extensionAttribute filters)](https://learn.microsoft.com/en-us/graph/aad-advanced-queries)
- [Grouper, prior art](https://github.com/Kungsbacka/Grouper)
- [Azure Static Web Apps hosting plans](https://learn.microsoft.com/en-us/azure/static-web-apps/plans)
- [Static Web Apps API constraints (managed functions: no managed identity)](https://learn.microsoft.com/en-us/azure/static-web-apps/apis-functions)
- [Static Web Apps Standard price (USD 9 per app)](https://www.azuredive.net/2025/09/azure-static-web-apps-in-depth/)
- [Bring your own functions to Static Web Apps (supported plans)](https://learn.microsoft.com/en-us/azure/static-web-apps/functions-bring-your-own)
- [Azure Functions pricing (Consumption free grant)](https://azure.microsoft.com/en-us/pricing/details/functions/)
- [Cosmos DB free tier (not for serverless)](https://learn.microsoft.com/en-us/azure/cosmos-db/free-tier)
- [Container Apps billing (free grant, scale to zero)](https://learn.microsoft.com/en-us/azure/container-apps/billing)
- [memberOf dynamic rules (preview ends 3 Nov 2026)](https://learn.microsoft.com/en-us/entra/identity/users/groups-dynamic-rule-member-of)
