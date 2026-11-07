# Component Design: API

Oct 9, 2026 · @Dodoe

The API is a PowerShell Function App linked to the Static Web App; it serves the web app and loads the engine module for validation and preview. Part of Doc.

## Decisions

The API is a REST API under `/api`, reachable only through the Static Web App, and it never writes group members itself: it stores configuration, checks rules with the engine module and starts runbook jobs.

| Topic | Decision |
| --- | --- |
| Hosting | Azure Functions, Consumption plan on Windows (Flex Consumption isn't listed for linked backends yet; see Infrastructure), PowerShell 7.4, linked to the Static Web App (Standard plan) |
| Access | Linking makes the Static Web App the only allowed caller; no public function keys |
| Identity | User-assigned managed identity "api": Cosmos DB data access, read-only Graph, start runbook jobs |
| Group writes | None; only the runbooks with the "engine" identity change groups |
| Rule checks | Same engine module as the runbooks (`Test-DgRule`, `Get-DgPreview`), so preview and sync never disagree |
| Roles in the MVP | Two roles from Entra app roles: Admin (change everything) and Reader (view groups, runs, audit, settings; run previews); sign-in is limited to users holding one of them |
| Format | JSON; errors as RFC 9457 problem details |

## Request path

&#91;embedded content: request path · browser to back ends\]

The browser only talks to the Static Web App, which signs the user in and forwards `/api` calls to the linked Function App. The API reads and writes configuration in Cosmos DB, reads directory data from Graph and starts runbook jobs; changing group members stays with the runbooks.

## Endpoints

Eighteen endpoints cover the five screens and the deployment check; every write goes through one of the definition, settings or approval endpoints and lands in the audit trail.

| Method and path | Purpose | Notes |
| --- | --- | --- |
| GET /api/me | Signed-in user and roles | Used by the web app on start |
| GET /api/definitions | List with status fields | Filters: type, result, enabled, search |
| POST /api/definitions | Create | Validates rule; returns ETag |
| GET /api/definitions/{id} | One definition | Returns ETag |
| PUT /api/definitions/{id} | Update | Requires If-Match |
| DELETE /api/definitions/{id} | Delete definition | Releases the group, never deletes it; requires If-Match |
| POST /api/definitions/{id}/sync | Sync now | See Sync now and approvals |
| POST /api/definitions/{id}/approve | One-time approval | Change limit or adoption |
| GET /api/definitions/{id}/runs | Run records, newest first | Paged, 30 days |
| GET /api/runs | Latest runs across all definitions | Activity overview |
| POST /api/rules/validate | Check rule text | Errors with positions; called while typing |
| POST /api/preview | Members a definition would have now | Accepts an unsaved definition |
| GET /api/settings | Organisation settings |  |
| PUT /api/settings | Update settings | Requires If-Match |
| GET /api/audit | Change history | Filter by definition, user, date |
| GET /api/directory/users?search= | People picker | Graph, read-only |
| GET /api/directory/groups?search= | Group picker (target, adopt, memberOf) | Shows type and whether on-prem synced |
| GET /api/health | Deployment check | Anonymous; returns only the version and "ok", no data |

## Authentication and authorisation

Sign-in happens entirely in the Static Web App; the API trusts a request only because it can arrive through the Static Web App and nowhere else.

1. **Sign-in:** custom Entra provider on the Static Web App, restricted to the tenant. The app registration defines two app roles, Admin and Reader, has "assignment required" on, and has one Entra group assigned to each role (e.g. the IT admins to Admin, the service desk to Reader). Nobody else gets a token.
2. **Route rules:** `staticwebapp.config.json` allows `/api/*` and all pages only for the role `authenticated`; anonymous requests are redirected to sign-in.
3. **Link lock:** linking the Function App adds an identity provider that gives the Static Web App exclusive access; direct calls to the function URL are refused.
4. **Caller identity:** the API reads the `x-ms-client-principal` header (Base64 JSON with userDetails and userRoles) and refuses requests without it. The user's UPN goes into audit records.
5. **Roles:** after sign-in, the Static Web App calls a small roles function (`/api/roles`, the Standard plan's rolesSource) that turns the token's `roles` claim into the app roles `admin` or `reader`. Route rules allow GET endpoints and preview for both roles, every write only for `admin`, and the API checks the same again in one `Assert-DgRole` call per endpoint. The web app hides edit controls for readers.

To verify in step 3: that the header reaches a linked Function App the same way it reaches managed functions, and whether the Entra object ID can be added (the header carries no claims).

## Validation and preview

Both run the engine module inside the API, so a rule that passes here behaves the same in the runbook.

**Validate** (`POST /api/rules/validate`): parses the rule and returns every error with position, e.g. `{"position": 34, "message": "expected a value after -eq"}`. The web app calls it 400 ms after the user stops typing. Fast and cheap: no Graph calls, except checking that group IDs in memberOf exist.

**Preview** (`POST /api/preview`): evaluates a saved or unsaved definition against live data and returns:

- member count and the first 200 members,
- users excluded by the implicit filters, with the reason,
- the difference to the current target group: who would be added and removed,
- whether the change limit would block it.

The preview reads users and groups through Graph. For Exchange group types it cannot run Exchange cmdlets (the "api" identity has no Exchange rights), so users without a mail address are flagged as "probably no Exchange recipient"; the exact check happens at sync. A preview takes a few seconds in a large tenant, so the web app runs it on a button, not while typing.

## Writes: concurrency and audit

Every write is guarded by an ETag and leaves an audit record; two admins can never silently overwrite each other.

- **ETag:** GET returns the document's ETag; PUT and DELETE must send it in `If-Match`. If someone changed the document meanwhile, the API returns 412 with the current version and who changed it last; the web app shows "changed by X at 14:02, reload or compare".
- **Status fields are read-only for the API:** status lives in a separate container that only the engine writes; the API merges it into responses, so an admin's save never touches a run's status.
- **Audit record per write:** who (UPN), when, action (create, update, delete, approve, sync now, settings), definition ID, and the changed fields with old and new values.
- **Atomic with the change:** audit records live in the same container and partition as their definition, so the API writes both in one Cosmos DB transactional batch.
- **Delete:** removes the definition, keeps its audit history and run records until they expire, and releases the target group unchanged.

## Sync now and approvals

**Sync now** (`POST /api/definitions/{id}/sync`):

1. Writes `SyncRequestedAt` and `SyncRequestedBy` on the definition (with its ETag) and an audit record.
2. Starts a job of the matching runbook through the Automation REST API (Job – Create) with Mode = SyncNow and the DefinitionId.
3. Returns 202 with the job ID; the web app polls the definition's status until LastSyncUtc moves past the request.

If starting the job fails, the request stays on the definition and the next scheduled run handles it; the response says so. Repeated clicks within one minute return the existing request instead of starting more jobs.

**Approve** (`POST /api/definitions/{id}/approve`) covers the two cases where the engine waits for a human:

| Case | What the approval does |
| --- | --- |
| Change limit blocked a run | Allows the next run to exceed the limit once, for exactly the diff the preview showed; a bigger diff blocks again |
| Adoption dry run done | Confirms the takeover; the next run writes the full membership |

Approvals store who approved and the diff size they saw, and end up in the audit trail.

## Errors, limits and performance

All errors use one shape (RFC 9457 problem details), so the web app shows them the same way everywhere.

```json
{
  "type": "https://dg/errors/validation",
  "title": "Rule is not valid",
  "status": 400,
  "errors": [{ "field": "rule", "position": 34, "message": "expected a value after -eq" }]
}
```

| Status | When |
| --- | --- |
| 400 | Invalid input or rule |
| 401 / 403 | No signed-in user / role not allowed |
| 404 | Definition not found |
| 409 | Target group already linked to another definition |
| 412 | ETag mismatch, someone else changed it |
| 429 | Graph throttled the preview; retry after the given seconds |
| 500 | Unexpected; the response carries a correlation ID that matches the function log |

- **Cold start:** with no always-ready instance, the first request after idle loads PowerShell and the modules and takes a few seconds; afterwards requests are fast. An always-ready instance would remove that but costs a fixed monthly amount, so it stays off in the MVP.
- **Preview cache:** the user snapshot is cached in the function instance for 5 minutes, so a second preview right after the first is fast.
- **Limits:** rule text up to 10,000 characters (same as the engine); preview returns at most 200 members per list; pages of 50 for lists.

## Project structure and tests

One Function App, one HTTP function per resource; shared code lives in a small helper module next to the engine.

```text
src/Api/
  host.json                 route prefix stays "api" (required for linked backends)
  requirements: none        managed dependencies off; modules ship in Modules/
  Modules/
    DgEngine/               same build as the runbooks
    DgApi/                  Assert-DgRole, Get-DgCaller, Write-DgAudit, New-DgProblem, Start-DgRunbookJob
    Microsoft.Graph.Authentication/
  me/  definitions/  definition-sync/  definition-approve/  runs/
  rules-validate/  preview/  settings/  audit/  directory/
```

- **Unit tests (Pester):** each function with mocked Cosmos DB, Graph and Automation calls; every status code in the table above.
- **Contract:** an OpenAPI file in the repo describes all endpoints; the web app's TypeScript types are generated from it, so API and UI cannot drift apart silently.
- **Smoke test after deploy, without any user account:** the pipeline calls `/api/health` through the Static Web App and checks that the returned version matches the release, then calls `/api/me` without signing in and expects a refusal, which proves the protection is active.

## Contract (step 0.3)

`src/Api/openapi.yaml` is now the binding version of the endpoints above. Precisions and additions:

- **`GET /api/me`** also returns `accessMode` (read-only or read-write) and the version, for the read-only banner.
- **`DELETE /api/definitions/{id}`** returns 409 with `referencedBy` when other rules reference the definition's group; `?force=true` deletes anyway after the web app's warning.
- **`POST /api/rules/validate`** always answers 200 with `valid`, errors (position, line, column, length, message, suggestion) and the group IDs the rule references; 400 is only for a malformed request.
- **`POST /api/preview`** takes either `definitionId` or an unsaved `definition`, and also returns the change-limit verdict and, with a compare group, the two compare lists.
- **`GET /api/directory/groups`** returns the flags the pickers need: Microsoft dynamic (with its rule), on-prem synced, role-assignable, already managed by RDG.
- **Missing `If-Match`** on PUT/DELETE returns 428; outdated returns 412 with who changed it last.
- **`POST /api/roles`** is the Static Web Apps roles source; it is internal and not counted in the 18 endpoints.
- Lists are paged with an opaque `continuationToken`, 50 items per page.

## Implementation notes (Phase 3)

- **The contract drives the code.** Every function folder has the same `run.ps1`; its route in `function.json` is the OpenAPI path, so DgApi finds the operation, and with it the allowed roles (`x-rdg-roles`), in the contract. Request bodies are validated against the contract's schemas with `Test-Json`. The API reads `Modules/DgApi/openapi.json`, generated from `openapi.yaml` by `npm run api:export`; the contract check fails when it is out of date.
- **The engine does the work.** DgApi calls the engine's store client, directory adapters and rule validator, so the API and the runbooks share one code path. `Get-DgPreview` became a public engine function.
- **Writes:** definition, settings, approval and sync-now writes go in one Cosmos DB transactional batch with their audit record; a lost race answers 412 with who changed it last. Audit records keep each changed field with its old and new value, and expire after the audit retention setting.
- **Group checks on save:** the group must exist and match the group type, and must not be synced from on-prem AD or role-assignable (400). It must not be managed by another definition (409). A Microsoft dynamic group can only be adopted, and the API then sets `convertFromDynamic`. `adopted` and `convertFromDynamic` are never taken from the request.
- **Read-only installations:** definitions can be created and changed (they run dry anyway). Approvals, and sync now of a group RDG would create or adopt, answer 409.
- **Preview:** the user list is cached per worker for five minutes. For Exchange types, users without a mail address are listed as `noExchangeRecipient`. Graph is retried only briefly, so throttling answers 429 with Retry-After.
- **500:** any operation can answer 500 with a Problem and the correlation ID, which also appears in the log line and the `x-correlation-id` header. The contract doesn't list 500 per operation.
- **Local runs without Azure:** `tools/Start-ApiLocal.ps1` serves the real routes and handlers over HTTP, with an in-memory store and an invented tenant. `tools/Build-ApiPackage.ps1` builds `api-<version>.zip`; with `-Local` it prepares `src/Api` for `func start`.
- **Gap:** deleting a definition doesn't clear the marker on its group, because the API has no group write rights. The engine could do it in a later version.

**Change in Phase 4.** `GET /definitions/{id}` also returns `includeUsers`, `excludeUsers` (UserRef lists) and `compareGroup` ({id, displayName}), all read-only, so the web app can show names. They come from Graph JSON `$batch` requests of 20 (`GET /users/{id}` and `/groups/{id}`, engine function `Get-DgDirectoryObjectById`), which need only User.Read.All and GroupMember.Read.All; `directoryObjects/getByIds` would need Directory.Read.All. IDs that no longer exist (404) are left out. If Graph fails, the definition is returned without these fields and a warning is logged. The list, writes and approvals don't carry them. Contract, `openapi.json`, fixtures and tests are updated.

## Open questions

- [x] Read-only role: in the MVP, as the Entra app role Reader.
- [x] Exchange preview: flagging users without a mail address is enough for the MVP; the sync filters exactly and reports Skipped.
- [x] Cold start: accepted for the MVP.
- [x] Smoke test: no test account; an anonymous health endpoint plus a check that protected endpoints refuse anonymous calls.

## Later versions

- Optional always-ready instance for the API (tfvars switch) to remove the cold start, at a fixed monthly cost.
