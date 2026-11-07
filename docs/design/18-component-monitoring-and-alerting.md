# Component Design: Monitoring and Alerting

Oct 9, 2026 · @Dodoe

Monitoring covers how IT sees what happened and gets told when something needs a human, without Log Analytics in the MVP. Part of Doc.

## Principles

- **The web app is where IT looks; email is for when a person must act.** Normal runs never send anything.
- **No Log Analytics in the MVP.** Signals come from Azure Monitor platform metrics, the run records in Cosmos DB, Automation job history and diagnostic logs written to storage.
- **Every alert says what to do.** Each one links to its entry under "What to do" below, which ships as part of the RDG docs.
- **Failures are loud by design.** The engine ends a job as Failed only when a group is Blocked or in Error (see Runbooks), so "job failed" always means "needs a human".

## In the web app

| Where | What it shows | Source |
| --- | --- | --- |
| Groups list | Status badge per group (OK, Warning, Blocked, Error, Dry run, Paused), members, last sync, last change; Blocked and Error sort to the top | `state` container |
| Group page | Last result with its message, warnings such as "3 disabled accounts and 1 guest excluded", link to its runs | `state` |
| Activity | Runs with changes, warnings or errors (quiet runs leave no record), 30 days. Each run: added and removed members, duration, engine version, Automation job ID with a link to the job in the Azure portal | `runs` container |
| Header | Pause banner; "engine not seen" warning when the last heartbeat is older than three ticks | heartbeat document in `state`, written once per tick |
| Audit | Who changed which definition or setting, and every approval | `config` |

## Alerts

All created by the `monitoring` module and sent to one action group.

| Alert | Signal | Fires when | Severity |
| --- | --- | --- | --- |
| Sync failed | Automation *Total Jobs*, runbook Sync-EntraGroups or Sync-ExchangeGroups, status Failed | more than 0 in 15 minutes | 2 |
| Sync not running | *Total Jobs*, runbook Sync-EntraGroups, any status | fewer than 1 in 60 minutes | 1 |
| Job stuck | *Total Jobs*, any RDG runbook, status Suspended or Stopped | more than 0 in 60 minutes | 2 |
| Certificate renewal failed | *Total Jobs*, runbook Renew-SignInCertificate, status Failed | more than 0 in 24 hours | 2 |
| API errors | Function App *Http5xx* | more than 5 in 15 minutes | 3 |
| Budget | Cost Management budget on the resource group | 80 % actual and 100 % forecast of `monthly_budget` | 3 |

Notes:

- **Pausing doesn't trigger "not running".** A paused engine still starts each tick and exits early, so the heartbeat and job count go on.
- **The certificate alert also covers expiry.** Renew-SignInCertificate fails on purpose when the app's newest key expires within 21 days, so one alert catches both a broken renewal and a certificate about to lapse.
- **Metric alerts are stateful.** A group that stays Blocked keeps the alert open; it sends one email when it fires and one when it resolves, not one per tick.
- **The email can't name the group.** Platform metrics don't carry that detail. The email links to the Activity page, which does.
- **Deploy pipeline failures** use Azure DevOps' own notifications to whoever started the run.

## Action group

- **Email** to the addresses in `alert_emails` (setting, at least one). A distribution list works.
- **Teams**: add the channel's email address to `alert_emails`. No webhook URL to store, so no secret.
- No SMS or phone in the MVP.

## Logs and retention

| What | Where | Kept |
| --- | --- | --- |
| Run records | Cosmos DB `runs` | 30 days (TTL) |
| Audit | Cosmos DB `config` | 60 days (setting) |
| Runbook job output and streams | Automation job history | 30 days (Automation's own limit) |
| API logs | Diagnostic setting *FunctionAppLogs* to the functions storage account | 30 days (lifecycle rule) |
| Deploy runs | Azure DevOps pipeline history | Azure DevOps retention |

- Every API log line carries the correlation ID that the error page shows, so one ID finds the request.
- Verbose engine logging is an app setting (see Runbooks); it adds detail to the job streams, not new alerts.
- **To verify in the test tenant:** that the diagnostic setting can write to a storage account with shared keys disabled. If it can't, API logs go to a small separate log storage account instead.

## What to do

- **Sync failed.** Open Activity and find the Blocked or Error run. Blocked: check the change and approve it on the group page, or fix the rule. Error: the run message names the cause (rule, permission, throttling); fix it and use Sync now.
- **Sync not running.** Check the Automation account: schedules enabled, runbooks published, the account not suspended. The last job's output usually says why.
- **Job stuck.** Open the job in the portal. A suspended job usually means an unhandled module error; stop it, and if it repeats, report it with the job ID.
- **Certificate renewal failed.** Open the last Renew-SignInCertificate job. Usual causes: the maintenance identity lost ownership of the sign-in app, or Key Vault didn't renew. As a fallback, upload the newest certificate to the app registration by hand.
- **API errors.** Look up the correlation ID from a user, or the latest entries in the API logs. Check that `/api/health` responds.
- **Budget.** Check the cost breakdown; the usual causes are a very short tick or a sync loop. Raise the tick or pause.

## Later versions

- Log Analytics and Application Insights as an opt-in setting: log alerts that name the group, a workbook, API traces.
- Alert emails that name the affected group and its change.
- A weekly digest email: groups, changes, warnings.
- A Cosmos DB throttling alert if installations grow large.

## Decisions

1. **Budget** is the setting `monthly_budget`, default USD 50.
2. **"Sync not running" stays Sev 1**; all other alerts Sev 2 or 3.
3. **Log Analytics** comes in a later version only if it adds something the MVP can't do (for example alerts that name the group).
