# RDG – Implementation Plan

Oct 9, 2026 · @Dodoe

## How we work

The plan builds everything that needs no tenant first, and pushes live testing as late as possible. Unit tests with mocked Graph and Exchange are part of every build step: they cost nothing to run and catch most mistakes before a tenant is involved.

**The step loop:**

1. Claude implements the step directly in the local repo folder (00\_RDG).
2. Claude reports what changed, which design doc it implements, and what to look at.
3. Review: Dodoe reviews, or hands the review to Claude, which then checks the step critically and fixes what it finds.
4. On approval the step is ticked here and the next one starts.
5. Dodoe commits and pushes when it makes sense; CI results from that push are checked then, and any fixes become part of the next step.

**A step is done when** its "Done when" line is true, CI is green, and Dodoe has approved it. Design changes discovered during a step go into the relevant design doc in the same pull request.

**Prerequisite:** a private GitHub repo with Claude connected. Made public later, when testing starts.

## Build without a tenant (Phase 0–7)

### Phase 0 – Foundation

- [x] **0.1 Repo skeleton.** Folder layout from CI/CD, `.gitignore`, `.editorconfig`, PSScriptAnalyzer settings, empty `ci.yml` that lints. *Done when:* layout matches the CI/CD doc and CI runs green on an empty project.
- [x] **0.2 Conventions.** Short `CONTRIBUTING.md` for ourselves: PowerShell and TypeScript style, naming, commit and branch rules, where design docs live. *Done when:* you agree with it.
- [x] **0.3 Contracts first.** `openapi.yaml` for all 18 endpoints and JSON schemas for every Cosmos DB document type (definition, state, run, audit, settings, heartbeat). *Done when:* both match the API and Data Model docs; they are the reference for every later step.

### Phase 1 – Engine (DgEngine)

- [x] **1.1 Tokenizer and parser.** Rule text to syntax tree, errors with line and position, never Invoke-Expression. *Done when:* every grammar example from the Engine doc parses, every broken one fails with a clear message.
- [x] **1.2 Evaluator.** All operators and property types, extension and directory-extension attributes, implicit filters (disabled, guests) with warnings. *Done when:* the conformance suite covers the full operator table and passes.
- [x] **1.3 Group references.** memberOf, managed groups re-evaluated in the same run, nested members setting, evaluation order, cycle detection. *Done when:* tests cover chains, cycles and unmanaged groups.
- [x] **1.4 Diff and safety.** Diff, include/exclude lists, change limit (setting, 10-change floor, first-fill exemption), dry run, forced dry run on adopt, read-only mode, compare group lists. *Done when:* every safety rule from the Engine doc has a test.
- [x] **1.5 Directory adapters.** Graph and Exchange behind one interface: read users and members, add and remove, create, rename, adopt incl. converting a Microsoft dynamic group to assigned. Mocked in tests. *Done when:* the engine never calls Graph or Exchange directly.
- [x] **1.6 Store and run orchestration.** Cosmos DB adapter, run lock, heartbeat, state and run records (quiet runs leave none), job result rules (Failed only on Blocked or Error). *Done when:* a full run works end to end against mocks.

### Phase 2 – Runbooks

- [x] **2.1 Sync runbooks.** Sync-EntraGroups and Sync-ExchangeGroups entry scripts, pause switch, verbose setting, build into single files with DgEngine inlined. *Done when:* the build output runs locally against mocks.
- [x] **2.2 Renew-SignInCertificate.** Key Vault read, keyCredentials update, removal of expired keys, deliberate failure under 21 days. *Done when:* tests cover all three cases.

### Phase 3 – API

- [x] **3.1 API skeleton.** Function App layout, `/api/health`, `rolesSource`, role checks, RFC 9457 errors, correlation IDs. *Done when:* runs locally with Azure Functions Core Tools.
- [x] **3.2 Definitions and settings.** CRUD with ETags, validation through DgEngine, audit in the same transactional batch, delete warning for referenced definitions. *Done when:* every endpoint matches `openapi.yaml`.
- [x] **3.3 Runs, preview, sync now, approve, directory search.** Starting runbook jobs, previews, approvals for change limit and adoption. *Done when:* all 18 endpoints are implemented and tested.

### Phase 4 – Web app

Developed against a mock API (Mock Service Worker) generated from `openapi.yaml`, so no backend or tenant is needed.

- [x] **4.1 Scaffold.** Vite, React, Fluent UI, routing, typed API client, sign-in shell, read-only banner. *Done when:* app runs locally on the mock API.
- [x] **4.2 Groups and group page.** List with status badges, Edit group, compare card, reader view. *Done when:* matches the mockups.
- [x] **4.3 Rule editor.** CodeMirror with syntax highlighting, autocomplete, live validation. *Done when:* the editor states from the mockups work.
- [x] **4.4 New, adopt and dialogs.** New group, adopt (incl. Microsoft dynamic groups), approve, conflict, delete. *Done when:* matches the mockups.
- [x] **4.5 Activity, Audit, Settings, empty and error states.** *Done when:* all 14 mockup screens exist in the app.

### Phase 5 – Infrastructure

- [x] **5.1 OpenTofu modules.** core, data, engine, app, monitoring, with the settings file and validation. *Done when:* `tofu validate` and TFLint pass and the example settings file plans without errors in structure.
- [x] **5.2 Bootstrap scripts.** Initialize-RdgAzure.ps1 and Initialize-RdgTenant.ps1 (incl. read-only grants and `-Remove`), New-RdgTestUsers.ps1. Written and reviewed, not run yet. *Done when:* each step in the Infrastructure doc maps to code.

### Phase 6 – CI/CD

- [x] **6.1 ci.yml complete.** All jobs from the CI/CD doc. *Done when:* a pull request shows every check.
- [x] **6.2 release.yml.** Bundle, checksums, attestation, release notes template. *Done when:* a test tag produces a downloadable bundle.
- [x] **6.3 Deploy pipeline.** `azure-pipelines.yml` template and Deploy-Rdg.ps1: fetch, plan, approve, apply, deploy code, web app, smoke test. *Done when:* reviewed end to end; it runs for the first time in Phase 8.

### Phase 7 – Operator docs

- [x] **7.1 Install guide and settings reference.** From zero to running, for the private tenant first. *Done when:* you could follow it without asking.
- [x] **7.2 Alert guide.** The "What to do" entries from Monitoring and Alerting. *Done when:* each alert links to its entry.

Phase 7 docs live in Claude Docs for now: [RDG – Install Guide](https://claude.ai/code/artifact/e606f7a5-5d22-40ab-b09b-37f8ea1fe3cd) (with the settings reference) and [RDG – Alert Guide](https://claude.ai/code/artifact/0f3d23e8-973a-4393-be69-3196024fd622). Alerts name their guide section; they link to it once `alert_guide_url` is set.

### Before publishing the repo

What has to be documented or changed before the repo goes public (after Phase 8, so the guides reflect what really happened):

**Repo and links**

- [ ] Create the public repo under your GitHub account and put `<owner>/rdg` into `rdgRepository` in `deploy/azure-pipelines.yml` (now `OWNER/rdg`) and into the attestation command in `.github/release-notes.md`
- [ ] Replace the claude.ai links in `docs/README.md`; those pages are private and nobody else can open them
- [ ] Branch protection on `main` with the CI checks required; Renovate app installed; secret scanning and Dependabot alerts on

**Operator docs into the repo**

- [ ] Install Guide and settings reference as `docs/install.md` and `docs/settings.md`, updated with what Phase 8 changed
- [ ] Alert Guide as `docs/alerts.md`, with headings that produce the anchors the alerts use (`#sync-failed`, `#sync-not-running`, `#job-stuck`, `#certificate-renewal-failed`, `#api-errors`)
- [ ] Set the default of `alert_guide_url` (infra/variables.tf) to the published `docs/alerts.md` address

**Design docs**

- [ ] Decide what of the component designs goes public: export as Markdown to `docs/design/`, or a shorter architecture overview
- [ ] Remove or reword HEKS references in published text: "Testing before HEKS" (bootstrap comments), the rule examples named after the HEKS EOP rule in `tests/rules/` (structure only, invented values, but the name stays)

**Project files that don't exist yet**

- [ ] `LICENSE` (choose one; the release bundle should include it)
- [ ] `SECURITY.md`: how to report a vulnerability privately
- [ ] `README.md` for adopters: what RDG does and doesn't do, screenshots of the mock web app, requirements (Entra ID Free; P1 for group-based role assignment; Exchange Online for mail groups), quick start pointing to the install guide, known limits (public endpoints, Exchange roles not scoped to RDG groups)
- [ ] Changelog or release-notes convention for v1.0.0

**Results of Phase 8**

- [ ] Every row of the Assumptions table checked, its outcome written into the affected guide (fallbacks that were needed become documented behaviour)
- [ ] Known issues from the test tenant listed in the README or the first release notes
- [ ] Cost estimate updated with the real monthly bill of the test installation

## Testing gate

Everything above is built and reviewed before anything touches a tenant. From here on, steps need Dodoe in the Azure portal and Entra admin center, so they go slower.

### Phase 8 – Private test tenant

- [ ] **8.1 Prerequisites.** Azure pay-as-you-go subscription with a budget alert, one Exchange Online Plan 1 licence, Azure DevOps project, repo made public. *Done when:* all four exist.
- [ ] **8.2 Install.** Stage 1, first pipeline run, stage 2, second pipeline run, smoke test green. Fix the install guide wherever it was wrong. *Done when:* sign-in works and `/api/health` shows the release version.
- [ ] **8.3 Seed and first groups.** Test users from New-RdgTestUsers.ps1; one Security, one M365, one mail-enabled security group and one distribution list created by RDG. *Done when:* members match the rules after dry run and approval.
- [ ] **8.4 Safety and lifecycle.** Change limit block and approve, adopt with forced dry run, rename on adopt, conflict and delete dialogs, pause switch, read-only mode switch both ways. *Done when:* each behaves as in the Engine doc.
- [ ] **8.5 Migration and compare.** Create a Microsoft dynamic group, compare it, adopt it, confirm members are kept. *Done when:* the compare lists are empty and the group is assigned and synced.
- [ ] **8.6 Operations.** Force a certificate renewal, trigger each alert once, run an upgrade to a new version and a rollback. *Done when:* every alert email arrived and both pipeline runs passed.
- [ ] **8.7 Release v1.0.0-rc.** Fixes from 8.2–8.6 merged and tagged. *Done when:* a clean install of the tag passes 8.2 and 8.3 again.

### Phase 9 – HEKS read-only

- [ ] **9.1 Install at HEKS** with `access_mode = read-only`, region Switzerland North, real Admin and Reader groups. *Done when:* smoke test green.
- [ ] **9.2 Rebuild the existing dynamic groups** as RDG definitions with compare groups, starting with the EOP Strict group. *Done when:* compare lists are empty or every difference is explained.
- [ ] **9.3 Observe** for one to two weeks: run times, warnings, alerts, cost. *Done when:* nothing unexplained is left.

### Phase 10 – HEKS live

- [ ] **10.1 Switch to read-write.** Stage 2 rerun, pipeline run. *Done when:* write grants are in place and all definitions did their forced dry run.
- [ ] **10.2 Migrate group by group.** EOP Strict first, one group at a time, each through dry run and approval. *Done when:* all planned groups are managed by RDG.
- [ ] **10.3 Release v1.0.0.** *Done when:* tagged and the HEKS installation runs on it.

## Assumptions to verify in the test tenant

Things the design relies on that the docs couldn't fully confirm. Each is checked in Phase 8; a failure changes the design doc named.

| Assumption | Checked in | Fallback | Doc |
| --- | --- | --- | --- |
| Converting a Microsoft dynamic group to assigned keeps its members | 8.5 | Snapshot members first and re-add them | Engine |
| API logs can be written to a storage account with shared keys off | 8.2 | Small separate log storage account | Monitoring and Alerting |
| Windows Consumption Function App runs from a blob package with the api identity, no Azure Files | 8.2 | Elastic Premium plan (more cost) | Infrastructure, CI/CD |
| Static Web App picks up a renewed certificate via thumbprint `*` | 8.6 | Pipeline restarts the app after renewal | Identity and Access |
| Exchange role group with a managed identity covers all distribution-group cmdlets incl. `-BypassSecurityGroupManagerCheck` | 8.3 | Add the missing role to "RDG Engine" | Identity and Access |
| Read-only grants are enough for full dry runs, compare and Exchange reads | 8.4 | Add the missing read permission | Identity and Access |
| sipProxyAddress equals the SIP: entry of proxyAddresses (without the prefix), and Entra's evaluation of null with the negated operators matches RDG's | 8.5 (compare groups) | Adjust the property map or the operator; the compare lists show the difference | Engine |
| Invoke-MgGraphRequest errors carry the HTTP status and Retry-After where the engine looks (exception Data or Response); the SDK's own retry handler stacks with the engine's | 8.4 | Adjust Get-DgTransientError; a 404 that isn't recognised would turn "group missing" into an error | Engine |
| Cosmos DB accepts the managed identity's token for the account endpoint (Get-AzAccessToken -ResourceUrl https://\<account>.documents.azure.com) and the cross-partition query SELECT \* FROM c WHERE c.type = @type | 8.4 | Token for https://cosmos.azure.com instead; query per partition | Engine, Data model |
| Get-DistributionGroup -Filter "ExternalDirectoryObjectId -eq '\<id>'" finds the group, Get-DistributionGroupMember returns ExternalDirectoryObjectId and RecipientType, and Remove-DistributionGroupMember accepts the recipient GUID | 8.3 | Look groups and members up through Get-EXORecipient | Engine |
| A new Exchange group gets its Entra object ID within a minute (the engine polls 12 × 5 s) | 8.3 | Raise CreateWaitAttempts. If it still times out, the run errors with the Exchange GUID and IT links the group as an existing target | Engine |
| The Automation identity endpoint (IDENTITY\_ENDPOINT, IDENTITY\_HEADER, client\_id) issues tokens for Cosmos DB and Key Vault in the PowerShell 7.4 runtime environment, and $PSPrivateMetadata.JobId is set there | 8.4 | Add Az.Accounts to the runtime environment (the engine falls back to Get-AzAccessToken); without a job ID the engine uses a new GUID | Runbooks |
| Connect-ExchangeOnline -ManagedIdentity -ManagedIdentityAccountId works together with -CommandName | 8.3 | Drop -CommandName (slower connect, same function) | Runbooks |
| With Application.ReadWrite.OwnedBy, GET /applications(appId='…')?$select=id,keyCredentials returns the key values, and a PATCH of keyCredentials with all kept keys plus the new one succeeds | 8.6 | Rebuild the kept keys from Key Vault's certificate versions instead | Identity and Access |
| The API runs under Azure Functions Core Tools (func start after tools/Build-ApiPackage.ps1 -Local); the Core Tools download was blocked in the build environment, so only the local host script was run | 8.2 | Fix run.ps1 or profile.ps1; the handlers are already tested without the host | API |
| A linked Function App receives x-ms-client-principal with userDetails and the rolesSource roles, as managed functions do | 8.2 | Read the roles from the token claims instead | API, Identity and Access |
| The Cosmos DB REST API accepts transactional batches (x-ms-cosmos-is-batch-request, atomic) and reports a failed operation's status as the engine expects | 8.2 | Write the change first, then the audit record (not atomic) | API, Data model |
| Job – Create (api-version 2024-10-23) works for the api identity with Automation Job Operator and Runbook Operator, and the portal link https://portal.azure.com/#resource\<account>/jobs/\<id> opens the job | 8.2 | Adjust the role or the link format | API |
| Static Web Apps custom Entra sign-in with rolesSource /api/roles works with the config in src/Web/public (deployment replaces \_\_TENANT\_ID\_\_ and \_\_KEY\_VAULT\_NAME\_\_; the certificate comes through the Key Vault reference with the system identity, thumbprint `*`); an expired session reaches the app as a 302 to /.auth/login/aad, which the app turns into a full-page sign-in | 8.2 | Adjust staticwebapp.config.json (routes, responseOverrides) and the client's signed-out check | Web App, Identity and Access |
| Group picker search: the API matches by prefix (startswith), so "board" doesn't find MESG-Board as the adopt mockup shows; the mock matches word prefixes | 8.4 | Switch Find-DgDirectoryObject to $search with ConsistencyLevel: eventual, or accept prefix search | API, Web App |
| Graph JSON $batch (GET /users/{id} and /groups/{id}, 20 per batch) returns names for GET /definitions/{id} with the api identity's read grants (User.Read.All, GroupMember.Read.All) | 8.4 | The API already returns the definition without names; the web app then shows the IDs | API |
| azurerm creates a PowerShell 7.4 runbook in a runtime environment from content alone (the provider doc says the API wants publish\_content\_link too) | 8.2 | Add publish\_content\_link to a pinned raw URL of the release's placeholder | Infrastructure |
| An Automation variable created without a value (DG\_MarkerExtension, DG\_SignInAppId while off) reads as $null in the runbook | 8.2 | Store "none" and treat it as off in the runbook entry scripts | Infrastructure, Runbooks |
| Container-scoped Cosmos DB SQL role assignments (/dbs/rdg/colls/\<name>) are enough for the engine's and api's REST calls, including cross-partition queries | 8.2 | Assign the same roles at database scope | Identity and Access, Data model |
| Continuous backup (7 days, free tier of continuous) is accepted on a serverless Cosmos DB account | 8.2 | Drop the backup block (periodic backup, the default) | Infrastructure |
| The pipeline's conditioned RBAC Administrator can create exactly the role assignments OpenTofu makes (Key Vault Certificate User, Automation Job and Runbook Operator, Storage Blob Data Owner and Contributor) | 8.2 | Fix the role list in Get-RdgPipelineRole (a test keeps it in step with the modules) and rerun stage 1 | Identity and Access |
| New-ServicePrincipal -AppId \<client ID> -ObjectId \<object ID> registers the engine's managed identity in Exchange, and Add-RoleGroupMember accepts it in the custom role group | 8.2 | Assign the roles to the service principal directly (New-ManagementRoleAssignment -App) | Identity and Access |
| "Sync not running" fires when no Sync-EntraGroups job ran in an hour, although the metric then has no data rather than 0 | 8.6 | Alert on missing data, or a heartbeat check in the API's health endpoint | Monitoring and Alerting |
| OpenTofu's azurerm backend, provider and azure\_vault key provider all sign in through the Azure DevOps service connection (ARM\_ADO\_PIPELINE\_SERVICE\_CONNECTION\_ID, SYSTEM\_ACCESSTOKEN, SYSTEM\_OIDCREQUESTURI) and refresh the token during a long apply | 8.2 | Pass the task's idToken as ARM\_OIDC\_TOKEN (short runs only), or use the AzureCLI task and ARM\_USE\_CLI | CI/CD |
| PUT runbooks/{name}/draft/content with Content-Type text/powershell, then POST publish (api-version 2024-10-23), replaces a runbook in a runtime environment and keeps its runtime environment | 8.2 | Import-AzAutomationRunbook, then set the runtime environment again | CI/CD |
| The first web deploy (before stage 2: no certificate in Key Vault, no AAD\_CLIENT\_ID) is accepted by Static Web Apps; sign-in starts working after stage 2 and the second run | 8.2 | Skip DeployWeb while signin\_client\_id is empty | CI/CD, Web App |
| Static Web Apps CLI 2.0.10 deploys with the token from SWA\_CLI\_DEPLOYMENT\_TOKEN and --env production on a hosted ubuntu-24.04 agent | 8.2 | AzureStaticWebApp@0 task with the token as a secret input | CI/CD |
| release.yml on a test tag: CI as a reusable workflow, Save-PSResource of Microsoft.Graph.Authentication, actions/attest@v4 and a draft release with both files | 8.1 | Fix the workflow; the bundle itself is built and tested in CI on every pull request | CI/CD |
