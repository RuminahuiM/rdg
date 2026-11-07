# Component Design: Data Model

Oct 9, 2026 · @Dodoe

The data model is the Cosmos DB for NoSQL (serverless) layout shared by engine and API. Part of Doc.

## Decisions

Three containers, each written by exactly one identity: the API owns configuration, the engine owns everything a run produces. No document is ever written by both, so admin edits and sync runs can never overwrite each other.

| Topic | Decision |
| --- | --- |
| Account | Cosmos DB for NoSQL, serverless, key authentication disabled, Entra roles only |
| Database | `rdg` |
| Containers | `config` (API writes), `state` (engine writes), `runs` (engine writes) |
| Partition key | `/pk` in all three; a definition's ID for everything belonging to one definition, fixed values for global documents (`settings`, `lock`, `system`) |
| Document types | A `type` field in every document: definition, settings, audit, status, lock, run |
| Atomic audit | Audit records sit in `config`, in the same partition as their definition, so a change and its audit record are written in one transactional batch |
| Access | Built-in Data Reader / Data Contributor roles, assigned per container |
| IDs | Definitions: `def-` plus a ULID (sortable by creation time); other documents derive their ID from it |

## Containers and access

Each container has one writer; the other identity can only read it. Roles are assigned per container, the narrowest scope Cosmos DB offers.

| Container | Holds | api (Function App) | engine (runbooks) | Default time-to-live |
| --- | --- | --- | --- | --- |
| `config` | Definitions, settings, audit records | Data Contributor | Data Reader | None |
| `state` | Status per definition, run locks | Data Reader | Data Contributor | None |
| `runs` | Run records for the Activity screen | Data Reader | Data Contributor | 30 days |

The pipeline identity has no data access at all; it only manages the account and containers through Azure Resource Manager.

## Container config

Everything IT decides lives here: one definition document per group, one settings document, and the audit trail next to what it describes. Only the API writes; the engine reads.

**Definition** (`pk` = its own ID)

```json
{
  "id": "def-01JA7K3M9Q", "pk": "def-01JA7K3M9Q", "type": "definition", "schemaVersion": 1,
  "name": "EOP Strict – Management",
  "groupType": "MailEnabledSecurity",
  "target": { "mode": "existing", "groupId": "0b7d…", "displayName": "MESG-EOP-Strict",
              "adopted": false, "renameOnAdopt": false },
  "rule": "(user.extensionAttribute3 -in [\"STIFTRAT\",\"DIR1\"]) -or (user.extensionAttribute3 -startsWith \"SRV\")",
  "includeUserIds": ["5f1c…"], "excludeUserIds": ["9a2e…"],
  "includeDisabled": false, "includeGuests": false,
  "frequencyMinutes": 15, "enabled": true, "dryRun": false,
  "changeLimitPercent": null, "allowEmpty": false,
  "syncRequest": { "at": "2026-10-09T09:52:00Z", "by": "dodoe@contoso.org" },
  "approval": null,
  "createdAt": "2026-10-06T08:47:00Z", "createdBy": "dodoe@contoso.org",
  "updatedAt": "2026-10-09T09:40:00Z", "updatedBy": "lea.keller@contoso.org"
}
```

- `target.mode`: `create`, `existing` or `adopt`. For `create`, `groupId` stays empty here; the engine records the new group's ID in its status document.
- `changeLimitPercent: null` means "use the organisation default".
- `approval`, when set: `{ "kind": "changeLimit" | "adopt", "diffHash": "sha256:…", "adds": 88, "removes": 0, "by": "…", "at": "…" }`. The hash identifies exactly the changes that were approved.

**Settings** (`id` and `pk` = `settings`)

```json
{
  "id": "settings", "pk": "settings", "type": "settings", "schemaVersion": 1,
  "paused": true, "pausedAt": "2026-10-09T10:15:00Z", "pausedBy": "dodoe@contoso.org",
  "verboseLogging": false,
  "changeLimitPercent": 50, "changeLimitMinChanges": 10,
  "newGroupsDryRun": true, "nestedMembers": true,
  "frequencyOptions": [3, 5, 15, 30, 60, 360, 1440],
  "naming": { "prefix": { "enabled": true, "text": "DG-" }, "suffix": { "enabled": false, "text": "" } },
  "marker": { "enabled": false, "exchangeCustomAttribute": 15 },
  "auditRetentionDays": 60
}
```

**Audit record** (`pk` = the definition's ID, or `settings`)

```json
{
  "id": "aud-01JA9P2X4C", "pk": "def-01JA7K3M9Q", "type": "audit", "schemaVersion": 1,
  "at": "2026-10-08T16:40:00Z", "by": "lea.keller@contoso.org",
  "action": "update",
  "changes": [ { "field": "rule", "old": "… -eq \"FIELD\"", "new": "… -startsWith \"FIELD\"" } ]
}
```

Actions: create, update, delete, adopt, approve, syncNow, settings. Deleting a definition keeps its audit records in the same partition.

## Container state

The engine's own bookkeeping: one status document per definition and one lock document per runbook. Only the engine writes; the API reads status to show it.

**Status** (`id` = `status-` plus the definition ID, `pk` = the definition ID)

```json
{
  "id": "status-def-01JA7K3M9Q", "pk": "def-01JA7K3M9Q", "type": "status", "schemaVersion": 1,
  "groupId": "0b7d…",
  "lastSyncUtc": "2026-10-09T10:15:22Z", "lastResult": "OK",
  "memberCount": 42, "added": 1, "removed": 0, "skipped": 0,
  "excluded": { "disabled": 2, "guests": 1 },
  "lastError": null, "lastRunId": "run-5c1e…-def-01JA7K3M9Q",
  "handledSyncRequestAt": "2026-10-09T09:52:00Z",
  "pendingApproval": null,
  "usedApprovalHash": null,
  "lastWrittenMembersHash": "sha256:…"
}
```

- `lastResult`: OK, Warning, Blocked, Error, DryRun, WaitingForApproval.
- `groupId`: the group the engine created or manages; for `target.mode = create` this is the only place the new ID is stored.
- `pendingApproval`: set when the change limit blocked or an adoption waits, `{ "kind", "diffHash", "adds", "removes", "percent" }`; the app shows it in the approve dialog.
- `lastWrittenMembersHash`: hash of the member list after the last write; a different hash on the next run means someone changed the group by hand ("manual change detected").

**Lock** (`id` = `lock-Entra` or `lock-Exchange`, `pk` = `lock`)

```json
{ "id": "lock-Exchange", "pk": "lock", "type": "lock", "jobId": "5c1e…", "acquiredAt": "2026-10-09T10:15:01Z", "expiresAt": "2026-10-09T10:45:01Z" }
```

Taken with a conditional write (create, or replace with the ETag of an expired lock); released by deleting it. The engine checks `expiresAt` itself, so a crashed run blocks at most two ticks.

## Container runs

One record per definition and run that changed something, warned or failed, plus one per skipped or paused tick; quiet runs only update the status. Only the engine writes; the Activity screen reads. Default time-to-live 30 days, so old records disappear without any cleanup job.

```json
{
  "id": "run-5c1e…-def-01JA7K3M9Q", "pk": "def-01JA7K3M9Q", "type": "run", "schemaVersion": 1,
  "jobId": "5c1e…", "runbook": "Exchange", "mode": "Scheduled",
  "startedAt": "2026-10-09T10:15:05Z", "durationMs": 38210,
  "result": "OK", "dryRun": false,
  "addedCount": 1, "removedCount": 0, "skippedCount": 0,
  "added": [ { "id": "7e21…", "upn": "marco.rossi@contoso.org" } ],
  "removed": [],
  "excluded": { "disabled": 2, "guests": 1 },
  "manualChangesReverted": { "added": 0, "removed": 0 },
  "warnings": [], "error": null
}
```

- Added and removed lists keep the first 500 users each (the counts are always complete), which keeps a record well under the 2 MB item limit.
- Skipped and paused ticks use `pk` = `system` and `type` = `run`, with `result` = SkippedTick or Paused and no definition.

## Handoffs without shared writes

The API and the engine pass information through timestamps and hashes instead of clearing each other's fields; each side only ever writes its own container.

| Handoff | API writes (config) | Engine answers (state) | Done when |
| --- | --- | --- | --- |
| Sync now | `syncRequest.at` on the definition | `handledSyncRequestAt` after the sync | `handledSyncRequestAt >= syncRequest.at` |
| Approval | `approval` with the diff hash IT saw | `usedApprovalHash` when it writes that exact diff | Hashes match; a different diff needs a new approval |
| Group created | Definition with `target.mode = create` | `groupId` of the new group | Status has a `groupId` |
| Blocked run | Nothing | `pendingApproval` with hash, counts, percent | IT approves, or changes the rule |
| Deleted definition | Definition removed, audit kept | Status left behind, cleaned up by the next run | Status gone |

The app merges definition and status into one row per group, so nobody sees two documents.

## Schema versions and upgrades

Every document carries `schemaVersion`. Readers are tolerant and writers are strict, so an upgrade never needs downtime or a manual migration.

- **Additive changes** (new optional field): no version bump; readers use a default when the field is missing.
- **Breaking changes** (renamed or restructured field): version bump. Both API and engine can read the old and the new version for one release; the owner of the container upgrades a document whenever it writes it.
- **Bulk upgrade:** when a release needs every document upgraded, the owning component does it on its first start after deployment, guarded by a `schema` document in its own container so it runs once.
- **Rule of ownership:** only the API upgrades `config` documents, only the engine upgrades `state` and `runs` documents.

## Retention, size and cost

The data stays small because quiet runs leave no record: a run with no changes, warnings or errors only updates the status (last sync time), so the runs container holds meaningful events only. Costs stay at cents per month in the serverless model.

| Data | Retention | Mechanism |
| --- | --- | --- |
| Definitions, settings | Until deleted | – |
| Audit records | 60 days by default; organisation setting "Audit retention" | Time-to-live set on each record when it is written; a changed setting applies to new records |
| Status, locks | Until the definition is gone / the run ends | Engine cleanup |
| Run records | 30 days | Container default time-to-live |

- Limits that matter: 2 MB per document (run records cap their user lists), 20 GB per partition key (one definition never comes close), 100 operations per transactional batch.
- Indexing: default indexing, but the large `added` and `removed` arrays in run records are excluded from the index to save request units.

## Contract (step 0.3)

The JSON schemas in `schemas/cosmos/` are now the binding version of this model; valid examples live in `tests/Fixtures/cosmos/`. Additions and precisions compared with the examples above:

- **Definition:** `compareGroupId` (compare group), `target.convertFromDynamic` (adopting a Microsoft dynamic group), `target.mailNickname` (optional, for created mail-enabled groups). For `target.mode = create`, `groupId` must be absent; for `existing` and `adopt` it is required. `groupType` values: `Security`, `Microsoft365`, `MailEnabledSecurity`, `Distribution`.
- **Settings:** `updatedAt` and `updatedBy`.
- **Audit:** `definitionName` (so entries still read well after a delete); `ttl` is required.
- **Status:** `dryRunReason` (`definition`, `newGroup`, `adoption`, `readOnly`), `warnings`, and `compare` counts.
- **Run:** `engineVersion`, `definitionName`, `groupId`, `dryRunReason`, `skipped` list, `approval`, and `compare` lists. Skipped and paused ticks carry only `result` and `reason`.
- **New: heartbeat** (`state`, `pk = system`, one per runbook) with time, job, engine version, paused flag and access mode, for the "engine not seen" warning.
- **New: schema marker** (`id = schema`, `pk = system`, one per container) for the once-only bulk upgrade.
- IDs are full ULIDs (`def-` plus 26 characters); the shortened IDs above are illustrations.

## Open questions

- [x] Audit retention: deleted after a set number of days, organisation setting, MVP default 60 days.
- [x] Backup: no automatic backup in the MVP beyond what Cosmos DB includes by default.

## Later versions

- **Backup history:** versioned backups of definitions and settings, with restore from the app; once it exists, audit retention can stay short because older states remain recoverable.
- **Continuous backup:** optional point-in-time restore for the Cosmos DB account (extra cost), as a tfvars switch.
