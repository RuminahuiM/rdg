# Component Design: Runbooks

Oct 9, 2026 · @Dodoe

Two thin runbooks in Azure Automation call the engine on every tick: Sync-EntraGroups and Sync-ExchangeGroups. Part of Doc.

## Decisions

Both runbooks are the same short script with a different provider: they read their settings, call `Invoke-DgSync` and turn its result into a job status. All logic, including connecting to Graph, Exchange and Cosmos DB, lives in the engine module.

| Topic | Decision |
| --- | --- |
| Runbooks | Sync-EntraGroups (Security, M365) and Sync-ExchangeGroups (mail-enabled security, distribution lists) |
| Runtime | One PowerShell 7.4 runtime environment shared by both runbooks |
| Identity | User-assigned managed identity "engine"; client ID from an Automation variable; no secrets anywhere |
| Triggers | Tick schedules (default every 15 min) and sync now from the API |
| Overlap | One run per runbook at a time, enforced by the engine's lock in Cosmos DB |
| Job status | Failed when any definition is Blocked or in Error, so the metric alert fires; warnings alone stay Completed |
| Time limit | Azure stops cloud jobs after 3 hours; the engine stops itself at 2.5 hours and leaves the rest to the next tick |

## How a job runs

&#91;embedded content: runbook job · 2 triggers, 2 decisions\]

Both triggers start the same runbook. If another run of that runbook holds the lock, a scheduled job skips its tick and a sync-now job waits briefly. Warnings end as Completed; only Blocked or Error definitions fail the job and fire the alert.

## Parameters and configuration

Jobs take two parameters; everything else comes from Automation variables that OpenTofu sets. None of them is a secret.

| Job parameter | Values | Default | Set by |
| --- | --- | --- | --- |
| Mode | Scheduled, SyncNow | Scheduled | Schedule link or API |
| DefinitionId | Definition ID | empty | API, only with SyncNow |

| Automation variable | Example | Purpose |
| --- | --- | --- |
| DG\_EngineClientId | GUID | Client ID of the "engine" identity |
| DG\_TenantDomain | contoso.onmicrosoft.com | Required by Connect-ExchangeOnline |
| DG\_CosmosEndpoint | https://dg-xyz.documents.azure.com | Cosmos DB account |
| DG\_CosmosDatabase | dynamicgroups | Database name |
| DG\_TickMinutes | 15 | Used for the due check and the lock lease |
| DG\_AccessMode | read-only | The installation's access\_mode; anything other than read-write runs read-only |
| DG\_MarkerExtension | extension\_\<appId>\_rdgDefinitionId | Directory extension for the marker on Entra groups; empty when not set up |

Organisation settings such as the change limit, the pause switch or verbose logging are not Automation variables: they live in Cosmos DB, so IT changes them in the app without a deployment.

## Triggers: tick schedules and sync now

**Tick schedules.** OpenTofu creates 60/tick hourly schedules per runbook, offset evenly (default tick 15 min: starts at :00, :15, :30, :45), each linked with Mode = Scheduled. A scheduled run handles every definition of its provider that is due or has a pending sync-now request.

**Sync now.** The API does two things:

1. Writes `SyncRequestedAt` and `SyncRequestedBy` on the definition, so the request is never lost.
2. Starts a job of the matching runbook with Mode = SyncNow and the DefinitionId, through the Automation REST API (Job – Create). The "api" identity needs Automation Job Operator on the account plus Automation Runbook Operator on the two runbooks.

The SyncNow job tries to take the lock. If a scheduled run holds it, the job waits up to 2 minutes, checking every 15 seconds; if it still cannot get the lock, it exits as Completed with "deferred", and the next scheduled run picks up the request because it is still on the definition. Either way the request is cleared only after the definition has synced.

**Pause.** An organisation setting "Pause all syncing" makes every run exit right after start, logged as "paused". It is the kill switch if something looks wrong.

## Error handling and job status

One broken definition never stops the others: the engine finishes every due definition first and only then decides the job status. The job ends as Failed only when a human needs to look.

| Situation | Job status | Definition status | Alert |
| --- | --- | --- | --- |
| Everything synced | Completed | OK | No |
| Warnings (excluded users, a single add or remove failed, manual changes reverted) | Completed | Warning | No |
| At least one definition Blocked or in Error | Failed, after all others ran | Blocked or Error | Yes |
| Connection to Graph, Exchange or Cosmos DB failed | Failed | Unchanged; no run record, the job error names the connection | Yes |
| User snapshot incomplete | Failed, nothing written | Unchanged | Yes |
| Lock held by another run (scheduled) | Completed, "skipped tick" | Unchanged | Only via missing-run alert if it repeats |
| Paused by setting | Completed, "paused" | Unchanged | No |
| 2.5-hour self-stop | Failed | Finished ones updated, rest unchanged | Yes |

The job is marked Failed by throwing one summary error at the very end, e.g. `2 definitions blocked or failed: EOP Strict (change limit), Finance (rule error)`.

## Output and logging

The Activity screen reads run records from Cosmos DB; the job streams are the backup for deeper debugging and stay in Automation for 30 days.

- **Output stream:** one compact JSON line per definition (`{"definition":"…","result":"OK","added":3,"removed":1,"ms":2140}`) and one summary line per run.
- **Warning stream:** one line per warning, prefixed with the definition name.
- **Error stream:** only the final summary error that fails the job.
- **Verbose and progress streams:** off by default; the organisation setting "Verbose logging" in the app turns verbose on for troubleshooting, so all debugging stays in one place. OpenTofu deploys the runbooks with Automation's "Log verbose records" on, so the stream is kept whenever the engine writes to it.
- **Correlation:** every run record stores the Automation job ID, so the Activity screen links straight to the job in the portal.

## Runtime environment and packaging

All three runbooks link to one PowerShell 7.4 runtime environment; its packages are pinned and updated only by the pipeline. DgEngine is not a package: the build inlines it into each runbook as a dynamic module, so the engine version can't drift from the runbook. No Az module is needed: tokens for Cosmos DB and Key Vault come straight from the Automation identity endpoint.

| Package | Source | Why |
| --- | --- | --- |
| DgEngine | Inlined into each runbook file by tools/Build-Runbook.ps1 | The engine module |
| Microsoft.Graph.Authentication | PowerShell Gallery, pinned version | Token handling; the engine calls Graph with Invoke-MgGraphRequest instead of loading the large Graph SDK modules |
| ExchangeOnlineManagement | PowerShell Gallery, pinned version | Exchange cmdlets with managed identity |

- Runtime environments allow 100 MB of packages in total; using only Microsoft.Graph.Authentication keeps well below that.
- Runtime environments are created through the REST API only, so OpenTofu manages them with the azapi provider.
- A package update applies to linked runbooks automatically; jobs already running keep the old version.
- The runbook script itself is deployed by OpenTofu from the repo, not through Automation's source control (which supports only PowerShell 5.1).

## Runbook sketch

Both sync runbooks are built from `src/Runbooks/Sync-Groups.template.ps1`; only the provider differs. The build replaces the `#{{DgEngine}}` line with the module. All output and the job status come from `Write-DgRunbookResult`, so they are tested with the engine.

```powershell
param(
    [ValidateSet('Scheduled', 'SyncNow')]
    [string] $Mode = 'Scheduled',
    [string] $DefinitionId
)
$ErrorActionPreference = 'Stop'

#{{DgEngine}}   <- the build inlines the engine here

$config = @{
    ClientId        = Get-AutomationVariable -Name 'DG_EngineClientId'
    TenantDomain    = Get-AutomationVariable -Name 'DG_TenantDomain'
    CosmosEndpoint  = Get-AutomationVariable -Name 'DG_CosmosEndpoint'
    CosmosDatabase  = Get-AutomationVariable -Name 'DG_CosmosDatabase'
    TickMinutes     = [int](Get-AutomationVariable -Name 'DG_TickMinutes')
    AccessMode      = Get-AutomationVariable -Name 'DG_AccessMode'
    MarkerExtension = Get-AutomationVariable -Name 'DG_MarkerExtension'
}

Invoke-DgSync -Provider 'Exchange' -Mode $Mode -DefinitionId $DefinitionId -Config $config | Write-DgRunbookResult
```

**Renew-SignInCertificate** is built the same way and runs weekly as the "maintenance" identity. Its Automation variables: DG\_MaintenanceClientId, DG\_KeyVaultUri, DG\_SignInCertificateName and DG\_SignInAppId. It calls `Sync-DgSignInCertificate`, which reads the certificate from Key Vault, reads the app's keys with their values (`$select=keyCredentials` on the single application), keeps every key that hasn't expired, adds the Key Vault certificate if it's missing, writes `keyCredentials` once, and then fails on purpose if the newest key expires within 21 days.

## Open questions

- [x] Sync now: waits up to 2 minutes for a running scheduled run, then defers to the next tick.
- [x] Pause switch: one switch for all syncing, both providers at once.
- [x] Verbose logging: an organisation setting in the app, not an Automation variable, so debugging has one place.
