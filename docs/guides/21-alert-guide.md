# RDG – Alert Guide

Oct 12, 2026 · @Dodoe

RDG sends six alerts by email to `alert_emails`; each email names its section below, and links to it once the setting alert\_guide\_url points at a published copy of this guide. Alerts close by themselves once the condition is gone. No alert ever names a group or a person; the Activity page in the web app has those details.

| Alert | Fires when | Severity |
| --- | --- | --- |
| Sync failed | a sync job failed in the last 15 minutes | 2 |
| Sync not running | no Sync-EntraGroups job in the last hour | 1 |
| Job stuck | a runbook job was suspended or stopped in the last hour | 2 |
| Certificate renewal failed | Renew-SignInCertificate failed in the last 24 hours | 2 |
| API errors | more than 5 server errors from the API in 15 minutes | 3 |
| Budget | 80 % of the monthly budget spent, or 100 % forecast | – |

Severity 1 needs action today: groups stop following their rules. Severity 2 within a working day. Severity 3 when convenient, unless users complain.

## Sync failed

A sync job ended Failed: at least one group ended **Blocked** or **Error** in that run, or the run itself failed. Other groups in the same run were synced normally.

1. Open **Activity** in the web app, filter Result = Blocked or Error, last 24 hours.
2. **Blocked**: the change was larger than the change limit. Open the group, check the members it would add and remove. If they are right, approve once; if not, fix the rule. Nothing was changed in the tenant.
3. **Error**: the run panel's message names the cause:
   - *rule*: the rule no longer validates (for example a property that was removed); fix it on the group page.
   - *permission* (403): a tenant grant is missing; rerun bootstrap stage 2. After switching to read-write this is the usual cause.
   - *throttling* or *timeout*: Graph or Exchange was busy; the next tick usually succeeds. Repeated throttling: raise `tick_minutes`.
   - *group not found*: the target group was deleted outside RDG; delete or re-target the definition.
4. After the fix, press **Sync now** on the group and check the new run.

No run in Activity? The run itself failed before writing a record: open the job in the Automation account (see Where to look).

## Sync not running

No Sync-EntraGroups job started in the last hour, so no group follows its rule any more. This is the only severity 1 alert; act today.

1. **Settings in the web app**: is syncing paused? A pause stops changes but jobs still run, so a pause alone doesn't trigger this alert.
2. **Automation account > Schedules**: the `tick-NN` schedules exist and are enabled, and their next run is in the future. A schedule that expired or was disabled by hand: rerun the pipeline, which recreates them.
3. **Automation account > Runbooks**: Sync-EntraGroups is Published. "New" or a placeholder that throws "not been deployed" means the deploy step didn't run: rerun the pipeline.
4. **Automation account > Jobs**: the last job's output and exception usually name the cause.
5. **Azure status**: an Automation outage in the region shows on the Service Health page of the subscription.

Right after an install or a long pause, the alert can fire once before the first job runs; it closes by itself.

## Job stuck

A runbook job was **Suspended** or **Stopped**. Azure stops cloud jobs after 3 hours (fair share), and suspends them after an unhandled module error.

1. Open **Automation account > Jobs**, filter Status = Suspended or Stopped, and open the job.
2. **Stopped after about 3 hours**: the run was too long, usually one very large group or heavy throttling. Raise `tick_minutes`, or split the definition.
3. **Suspended**: the Exceptions tab names the error. Stop the job so it doesn't resume.
4. If it repeats with the same error, report it as an RDG issue with the job ID, the runbook name and the RDG version.

## Certificate renewal failed

The weekly Renew-SignInCertificate job failed. It fails on purpose when the sign-in app's newest key expires within 21 days, so this alert also warns of a lapsing certificate. When the key expires, nobody can sign in to the web app; the engine keeps running.

1. Open the last **Renew-SignInCertificate** job in the Automation account; its output names the cause.
2. *Expires within 21 days*: Key Vault didn't renew. In the app Key Vault, open the certificate `rdg-signin` and check its issuance policy (renew 60 days before expiry). Create a new version by hand if needed, then start the runbook.
3. *403 on the app*: the maintenance identity is no longer an owner of the sign-in app. Rerun bootstrap stage 2, which adds it again.
4. *403 on Key Vault*: the maintenance identity lost Key Vault Certificate User; rerun the pipeline.
5. **Fallback** if sign-in already broke: download the certificate's public part (.cer) from Key Vault and upload it under the app registration's Certificates & secrets. The Static Web App picks up the newest version by itself.

## API errors

The API answered more than 5 server errors (HTTP 5xx) in 15 minutes. Users see error messages in the web app; the engine is not affected.

1. Open `https://<web app>/api/health`. No answer: the Function App is down or restarting. Check it in the portal and restart it.
2. A user reported an error: the message shows a correlation ID; search for it in the API logs (see Where to look).
3. No report: open the newest API log file and look for `Error` entries. Usual causes: Cosmos DB throttling (wait), a missing permission after an upgrade (rerun stage 2), or a broken deploy (rerun the pipeline).
4. Right after a deploy, a few errors during the restart are normal and the alert closes by itself.

## Budget

The resource group spent 80 % of `monthly_budget`, or Azure forecasts 100 % by month end. Nothing stops; it's a heads-up. A normal installation costs about USD 26–27 a month.

1. Open **Cost Management > Cost analysis** for the resource group, grouped by resource.
2. **Automation** high: the tick is very short, or a sync loops. Raise `tick_minutes`, or pause syncing in the web app while you look.
3. **Cosmos DB** high: unusually many runs or audit records; check Activity for a group that changes on every run.
4. **Static Web App** has a fixed monthly price (Standard plan); it doesn't grow with use.
5. If the higher cost is expected, raise `monthly_budget`.

## Where to look

| Place | What you find | How to get there |
| --- | --- | --- |
| Activity (web app) | Every run of the last 30 days per group: result, added, removed, skipped, the run's message, a link to the job | Web app > Activity |
| Automation jobs | Every job with output, warnings and exceptions | Portal > `aa-<prefix>-<env>` > Jobs |
| API logs | Function App logs, kept 30 days | Portal > storage account `st<prefix><env><suffix>` > container `insights-logs-functionapplogs` |
| Alert history | Which alert fired when | Portal > Monitor > Alerts, filtered on the resource group |
| Audit (web app) | Who changed which group or setting, and when | Web app > Audit |
