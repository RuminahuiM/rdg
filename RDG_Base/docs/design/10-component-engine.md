# Component Design: Engine

Oct 9, 2026 · @Dodoe

The engine is the PowerShell module that evaluates rules and syncs members; runbooks and API are thin shells around it. Part of Doc.

## Decisions

The engine supports the full Entra user rule language, excludes disabled accounts and guests by default with a visible warning, can adopt existing groups on request, and tracks the groups it manages in its own registry.

| Topic | Decision |
| --- | --- |
| Rule language | Full parity with Entra dynamic user rules, so any existing rule pastes 1:1; plus include/exclude lists |
| Objects | Users only in v1; device rules later |
| Disabled accounts and guests | Excluded by default; each run records how many matched but were excluded, as a warning; a definition can opt back in |
| Existing groups | Only taken over with an explicit Adopt flag; the first run after adopting is always a dry run |
| Ownership | Engine-side registry (the definition's target group ID) by default; optional name prefix/suffix and optional marker attribute on the group |
| Language | PowerShell 7.4 module, no Invoke-Expression on rule text |
| Effort for full parity | Small for the parser (same grammar); the extra work is the property mapping, collection rules (`-any`, `-all`), dates, directory extensions and Direct Reports, mostly tests: roughly a few extra days with AI help |

## How a run works

&#91;embedded content: one engine run · 10 steps, 1 decision\]

Users and referenced groups are read once per run, every due definition is evaluated in memory, and only the differences are written. A definition that fails a safety check is marked Blocked and skipped; the others still sync.

## Rule language: properties

Rules use the Entra property names; the snapshot loader reads the matching Graph field and only the fields that the current definitions reference. Several Entra names differ from Graph, so the mapping lives in one table in the module and gets one test per row.

| Rule property | Graph field | Type |
| --- | --- | --- |
| accountEnabled | accountEnabled | Boolean |
| dirSyncEnabled | onPremisesSyncEnabled | Boolean |
| employeeHireDate | employeeHireDate | Date (Entra: preview) |
| objectId | id | String |
| city, country, companyName, department, displayName, employeeId, givenName, jobTitle, mail, onPremisesDistinguishedName, onPremisesSecurityIdentifier, passwordPolicies, postalCode, preferredLanguage, state, streetAddress, surname, usageLocation, userPrincipalName, userType | same name | String |
| mailNickName | mailNickname | String |
| facsimileTelephoneNumber | faxNumber | String |
| mobile | mobilePhone | String |
| telephoneNumber | businessPhones (first entry) | String |
| physicalDeliveryOfficeName | officeLocation | String |
| sipProxyAddress | to be confirmed, see Implementation notes | String |
| extensionAttribute1–15 | onPremisesExtensionAttributes.extensionAttributeN | String |
| extension\_\[appId\]\_\[name\] | same name, discovered per tenant | String |
| otherMails, proxyAddresses | same name | String collection |
| assignedPlans | assignedPlans (capabilityStatus, service, servicePlanId) | Object collection |
| memberOf | group resolver, see Group references | Group ID collection |
| Direct Reports for "id" | manager (expanded once per run, only if a rule uses it) | Special rule |

## Rule language: operators and syntax

The grammar follows Entra exactly, with three deliberate differences: property names are case-insensitive, there is no 3,072-character limit (the engine caps at 10,000), and regex matching has a 100 ms timeout per value.

| Group | Operators | Notes |
| --- | --- | --- |
| Comparison | -eq, -ne, -startsWith, -notStartsWith, -endsWith, -notEndsWith, -contains, -notContains | Strings case-insensitive; -contains is a substring match, not a collection test |
| Regex | -match, -notMatch | .NET regex, case-insensitive, 100 ms timeout |
| Lists | -in, -notIn | Value is `["a","b"]`; exact match per item |
| Dates | -le, -ge | Only employeeHireDate; `system.now -plus P1D` / `-minus` with ISO 8601 durations |
| Collections | -any, -all | Over otherMails, proxyAddresses (`_` = item), assignedPlans (`assignedPlan.field`), memberOf (`group.objectId`) |
| Logic | -not, -and, -or | Precedence: comparisons, then -not, -and, -or; parentheses override |
| Null | -eq null, -ne null | `null` without quotes; `-not` with null is an error, as in Entra |

Hyphens on operators are optional, as in Entra. Inside strings, a double quote is escaped with a backtick and a single quote is doubled.

```text
rule          = directReports | orExpr
orExpr        = andExpr { "-or" andExpr }
andExpr       = notExpr { "-and" notExpr }
notExpr       = [ "-not" ] primary
primary       = "(" orExpr ")" | collectionTest | comparison
comparison    = property operator value
collectionTest= property ("-any" | "-all") "(" itemExpr ")"
itemExpr      = orExpr over "_", "assignedPlan.<field>" or "group.objectId"
value         = string | number | "true" | "false" | "null" | list | dateValue
list          = "[" value { "," value } "]"
dateValue     = isoDateTime | "system.now" [ ("-plus" | "-minus") isoDuration ]
directReports = "Direct Reports for" string
property      = "user." name
```

## Parser and evaluator

Rule text goes through a tokenizer and a recursive-descent parser into a syntax tree; the evaluator walks that tree per user. Rule text is never executed as PowerShell.

- **Tokenizer:** splits into property paths, operators, strings, numbers, lists, parentheses; every token keeps its position.
- **Parser:** builds the tree following the grammar above. Errors name position and expectation, e.g. `Position 34: expected a value after -eq`. The API returns these to the rule editor while typing.
- **Validation after parsing:** unknown property, operator not allowed for that property type (e.g. `-ge` on department), invalid regex, unknown group ID in memberOf, length cap.
- **Compile once per run:** each definition is parsed once; the tree plus a list of referenced properties is cached for the run, so the snapshot loader knows which Graph fields to read.
- **Evaluation:** short-circuit for `-and` and `-or`; missing values count as null, so `user.department -eq "X"` is false for users without a department and `-ne` is true.
- **Result:** a set of user IDs per definition, then include/exclude lists and implicit filters are applied, in that order: rule result, minus implicit filters, plus includes, minus excludes. Excludes always win.

## Group references (memberOf)

A rule references groups with Entra's syntax, `user.memberof -any (group.objectId -in ['id1','id2'])`, and unlike Entra it can be combined with any other condition. How the members are found depends on the group:

| Referenced group | Members used | Why |
| --- | --- | --- |
| Managed by this tool | The referenced definition's result, evaluated in the same run (rule, filters, includes, excludes) | Never one sync cycle behind; no ordering between the two runbooks needed |
| Any other group | Its current members including nested members (transitive), read once per run; a tenant setting "Nested members" (default on) switches to direct members only | Nested is what people usually expect; Entra itself only uses direct members. Turning it off saves Graph calls in very large tenants |

- Each referenced definition is evaluated once per run and cached, however many rules use it.
- A referenced definition is evaluated even when it is disabled. If it was deleted, its group is an ordinary group again and is read live with its last members; that is why deleting a definition whose group other rules use needs a confirmation (API: 409 with the referencing definitions, then force). For an Exchange group, the members used are RDG's result before the Exchange recipient filter, so users without a mailbox still count for memberOf.
- Cycles (A uses B, B uses A, also longer chains) are detected before evaluation; every definition in the cycle gets LastResult = Error and nothing is written for them.

## Implicit filters: disabled accounts and guests

By default the engine drops users with accountEnabled = false and users with userType = Guest after the rule is evaluated. Each definition has two switches, IncludeDisabled and IncludeGuests, both off by default.

- The run record keeps a count per reason, e.g. `12 matched the rule but were excluded: 8 disabled, 4 guests`, shown as a warning line in Activity. It does not change LastResult, so groups that routinely match a few disabled accounts do not stay yellow forever.
- The preview lists excluded users separately, so IT sees them before saving.
- Users added through IncludeUsers bypass the filters: an explicit include is a deliberate choice.
- Exchange group types additionally drop users without an Exchange recipient (counted as Skipped, not as a warning).

## Group ownership: registry, adopt, naming, marker

The registry decides what the engine may touch: a group is managed only if a definition holds its ID. Naming and marker are optional extras for visibility, set per tenant in Settings.

| Option | Default | What it does |
| --- | --- | --- |
| Registry | Always on | Target group ID stored in the definition; the engine refuses any group not linked to exactly one definition |
| Name prefix / suffix | Off | Groups the engine creates get e.g. `DG-` in front or `  (dynamic) ` at the end; text configurable; adopted groups are renamed in place only if IT ticks Rename when adopting |
| Marker attribute | Off | Exchange groups: CustomAttribute N (number configurable) set to the definition ID. Entra groups: a directory extension property on the sign-in app registration, set to the definition ID. Makes managed groups visible in the portals and allows an Exchange management scope |

**Adopt an existing group:**

1. IT picks an existing cloud group as target and ticks Adopt.
2. The engine checks: cloud group (not synced from on-prem AD), group type matches, not linked to another definition, not a role-assignable group.
3. The first run is forced to dry run; the preview shows every member that would be removed.
4. After IT confirms, the definition owns the group: from now on the engine sets its full membership, and manual changes in the portal are reverted on the next run and shown as a warning in Activity ("manual change detected: 2 added, 1 removed, reverted").

**Renaming instead of recreating:** when a naming prefix or suffix is on, adopt can rename the group in place (Graph for Entra groups, Set-DistributionGroup for Exchange groups). The group ID, mail address and every reference to it, such as a Defender preset policy, stay intact; recreating the group would break those references, so the engine never does it.

Unlinking a definition (or deleting it) releases the group: membership stays as it is, the marker is removed if it was set.

## Diff and safety brakes

The engine compares the desired member set with the group's current direct members and writes only the difference; before writing, five checks can stop a definition. A stopped definition gets LastResult = Blocked, nothing is written for it, and the run ends as Failed so the alert fires.

| Check | Blocks when | Override |
| --- | --- | --- |
| Empty result | The rule returns 0 users while the group has members | Per definition: AllowEmpty |
| Change limit | Adds plus removes exceed the change limit, measured against current members. Organisation setting; MVP default 50 % (to be tightened to 40 % later); applies only from 10 changes up. Skipped on the first sync of a group the engine just created; on adoption, the forced dry run plus IT's confirmation is the one-time approval | Per-definition override, or approve once in the app |
| Ownership | Target group is not linked to exactly one definition | None |
| Source | Target group is synced from on-prem AD or is role-assignable | None |
| Snapshot health | The user snapshot is incomplete (paging error, or far fewer users than last run) | None; the whole run stops |

Nested groups and non-user members in the target group are left alone: the engine only adds and removes users.

## Writers: Graph and Exchange

Two writers share one interface (create group, read members, add, remove, set marker), so the diff logic does not care which system it talks to.

|  | Graph writer | Exchange writer |
| --- | --- | --- |
| Group types | Security, Microsoft 365 | Mail-enabled security, distribution list |
| Create | `POST /groups` | `New-DistributionGroup` (`-Type Security` for mail-enabled security) |
| Read members | `GET /groups/{id}/members/microsoft.graph.user`, paged | `Get-DistributionGroupMember -ResultSize Unlimited` |
| Add | `PATCH /groups/{id}` with `members@odata.bind`, 20 users per request | `Add-DistributionGroupMember -BypassSecurityGroupManagerCheck`, one per call |
| Remove | `DELETE /groups/{id}/members/{userId}/$ref`, bundled 20 per `$batch` | `Remove-DistributionGroupMember -BypassSecurityGroupManagerCheck` |
| Eligible users | All users | Only users with an Exchange recipient: read once per run with `Get-EXORecipient`, matched by object ID |
| Throttling | Honour `Retry-After`, exponential backoff | Retry on throttling errors with backoff |

A failed single add or remove does not stop the definition: it is retried once, then listed in the run record, and LastResult becomes Warning.

## Store, scheduling, run lock, reporting

The engine talks to Cosmos DB through a small store client and never holds keys: it gets an Entra token for the managed identity and uses ETags so it cannot overwrite an edit IT made during the run.

- **Due check:** a definition is due when it is enabled and `now >= LastSyncUtc + Frequency` (with one minute of tolerance), or when a sync-now request names it. Frequencies below the tick are raised to the tick.
- **Run lock:** one lock document per runbook with a lease of 2 × tick. A run that finds a valid lease exits as "skipped tick"; a crashed run's lease simply expires.
- **Status write:** at the end of each definition: LastSyncUtc, LastResult, MemberCount, Added, Removed, Skipped, Excluded, LastError. Written to the engine's own status document in the state container, never to the definition, so it cannot collide with an admin's edit.
- **Run record:** one document per definition and run that changed something, warned or failed, in the runs container (30-day time-to-live): result, added and removed user IDs (first 500 each), warnings, error text, Automation job ID, duration.

## Module structure and tests

The module exposes four public functions; everything else is private and testable without Azure.

| Public function | Used by | Does |
| --- | --- | --- |
| `Invoke-DgSync -Provider <Entra/Exchange> -Mode <Scheduled/SyncNow> [-DefinitionId]` | Runbooks | A full run for one provider |
| `Test-DgRule -Rule <text>` | API | Parse and validate, return errors with positions |
| `Get-DgPreview -Definition <obj>` | API | Members now, excluded users, diff against the target group |
| `Compare-DgWithEntra -Rule <text> -EntraGroupId <id>` | IT, migration | Runs a rule and compares the result with an existing Entra dynamic group, to prove parity before switching |

```text
src/DgEngine/
  DgEngine.psd1, DgEngine.psm1
  Public/      Invoke-DgSync, Test-DgRule, Get-DgPreview, Compare-DgWithEntra
  Private/
    Rules/     Tokenizer, Parser, Validator, PropertyMap
    Evaluate/  Evaluator, GroupResolver, ImplicitFilters
    Snapshot/  UserSnapshot, ExchangeRecipients
    Sync/      Diff, SafetyBrakes
    Writers/   GraphWriter, ExchangeWriter
    Store/     CosmosClient, RunLock, Reporter
tests/
  DgEngine/    Pester tests, mirroring Public/ and Private/<area>/
  Fixtures/    users.json, groups.json (invented test data)
  rules/       conformance suite: rule + user + expected result per case
```

- **Unit tests (Pester):** every grammar rule, every operator, every row of the property map, every safety brake.
- **Rule corpus:** a growing set of real-world rules with expected results, including the structure of the HEKS EOP rule with invented values (no real tenant data in the repo); every bug becomes a new entry.
- **Writers:** tested against mocked Graph and Exchange calls.
- **Parity:** before go-live, Compare-DgWithEntra runs against existing Entra dynamic groups in a test tenant.

## Read-only mode

An installation can run with `access_mode = read-only` (settings file). Used to test on the real production tenant before going live.

- **Enforced by permissions, not only by code.** Stage 2 grants only read rights (see Identity and Access), so even a bug can't change a group.
- **The engine treats every definition as dry run.** It still evaluates, diffs and writes run records and state, so Activity shows exactly what it would do. New groups appear as "would be created"; adoptions show their dry-run result and can't be approved.
- **Change limit and approvals** are evaluated and shown, but nothing is applied.
- **Going live:** set `read-write`, rerun stage 2, run the pipeline. Every definition then starts with the normal forced dry run once.

## Compare with a group

A definition can name an optional **compare group**: any existing group, typically the Microsoft dynamic group it is meant to replace.

- Each run reads the compare group's direct members and reports two lists: "only in RDG" and "only in compare group", with counts in the group's state and the lists in the run record.
- It only reads, so it works in read-only mode and costs one extra Graph call per definition.
- Typical use: paste the dynamic group's rule into RDG, set the dynamic group as compare group, and check the lists are empty before switching over.

## Migrating a Microsoft dynamic group

Adopting a group that is a Microsoft dynamic group works like any adoption, with two extra steps:

1. **The rule is pre-filled** from the group's `membershipRule`. The parser flags anything it reads differently.
2. **On approval the engine converts the group to assigned membership** (removes `DynamicMembership` from `groupTypes`, sets rule processing to Paused) and then syncs it. The group ID, mail address and every policy that references it stay the same.

To verify in the test tenant: that members are kept during the conversion. Microsoft's own sample does it the same way, but the docs don't say so explicitly.

## Scale at HEKS

About 2,000 users in the tenant, about 800 in the scope of RDG rules, and a modest number of groups. The engine reads all users once per run (a few paged Graph calls with `$select`), so a run is expected to take well under a minute, even at a 3-minute tick. No sharding or delta queries needed in the MVP.

## Open questions

- [x] Nested members of groups the tool does not manage: included by default, tenant setting to turn off.
- [x] Adopted groups: manual changes are reverted and shown as a warning; renaming happens in place, never by recreating.
- [x] Change limit: organisation setting, MVP default 50 %, later 40 %; from 10 changes up; skipped on the first sync of a newly created group; applies on adoption through the forced dry run and IT's confirmation.

## Implementation notes

- **sipProxyAddress:** the user's SIP address, used by Teams and formerly Skype for Business. Entra allows it in rules, but Graph v1.0 has no user field of that name. Likely source: the `proxyAddresses` entry that starts with `SIP:`. Step 1 verifies this against test users whose SIP address differs from their mail address. If Graph cannot provide it reliably, the validator rejects the property with a clear message instead of silently returning wrong results.
- **Memory:** the user snapshot lives in memory, and Azure Automation sandboxes have 400 MB. Step 1 measures memory per 1,000 users with the properties a typical rule set needs and documents the supported tenant size; if a tenant exceeds it, the loader reads only the properties referenced by due definitions, and sharding is the fallback.
- **Parser details (step 1.1):** where Entra's documentation is vague, the parser does this:
  - hyphens on all operators are optional, including `and`, `or`, `not`;
  - an en dash or em dash before an operator counts as a hyphen, because Microsoft's own examples contain `–ne`;
  - strings take double or single quotes; `` `" `` escapes a double quote, `''` a single quote; the documented form `` `"Sales`" `` without outer quotes is the text `"Sales"` with quotes;
  - typographic quotes (“ ”) are refused with a clear message;
  - unquoted text values are refused with the hint to add quotes;
  - `system.now` takes `-plus` and `-minus` with ISO 8601 durations, case-insensitive (`p1d`);
  - only the first syntax error is reported. Property names, operator/type combinations and regular expressions are checked by the validator in step 1.2.
- **Evaluation details (step 1.2):** decisions where Entra's documentation is silent:
  - negated operators are the exact opposite of their positive form, so `-notStartsWith`, `-notContains`, `-notMatch`, `-notIn` are true for users without the property (like `-ne`);
  - `-all` is true for an empty collection (needed for Entra's own example `-all (assignedPlan.servicePlanId -eq null)`);
  - numbers compared with text properties are compared as text (`user.employeeId -eq 4711`); booleans may also be written quoted (`"false"`); a date may be quoted;
  - Direct Reports includes the manager, as Microsoft documents;
  - memberOf accepts `-any (group.objectId -in [...])` and `-eq`; anything else inside memberOf is refused, as only that form is documented;
  - `sipProxyAddress` is read from the `SIP:` entry of proxyAddresses, without the prefix; to verify in the test tenant;
  - validation returns all errors after the first syntax error is fixed, and suggests the closest property name for typos.
- **Measured speed (step 1.2):** a HEKS-style rule with three conditions takes about 1.7 s for 2,000 users in plain PowerShell; a simple comparison about 0.25 s. Good enough for the MVP; if a tenant has many definitions, compiling rules to faster delegates is the obvious optimisation.
- **Group references (step 1.3):** a run evaluates the due definitions plus everything they depend on, dependencies first. Precisions:
  - a memberOf group RDG manages always uses that definition's result from the same run (after its filters), even if the definition is disabled or not due;
  - each group RDG doesn't manage is read once per run, nested or direct according to the setting;
  - errors stay per definition: a cycle names its path ("memberOf cycle: A -> B -> A", also a rule using its own group), a definition behind a failed one names it ("depends on A, which failed: ..."), a missing or unreadable group fails only the definitions that use it;
  - two definitions linked to the same group both fail, so neither overwrites the other.
- **Safety checks (step 1.4):** the plan checks in a fixed order, first match wins: source (synced from on-prem or role-assignable) → read-only installation → adoption not yet approved → definition dry run → first run of a new definition when "new groups start in dry run" is on → empty result → change limit. Precisions:
  - the empty check comes before the change limit, so an emptying rule always names the real reason;
  - the adoption approval also covers the first write, but only while its diff hash still matches; if the users changed meanwhile, IT approves again;
  - an approval is used once: the engine stores its hash and never reuses it;
  - a manual change (the group differs from what the engine last wrote) is reverted and makes the result Warning; a failed add or remove is not counted as a manual change on the next run;
  - warnings from includes ("always-include user not found") also make the result Warning;
  - snapshot health: an empty user list, or fewer than 80 % of the previous healthy count (from 20 users up), stops the run; the count lives in the heartbeat and is only updated by a healthy run.
- **Writers (step 1.5):** Graph adds go 20 per PATCH; if a chunk fails, its users are added one by one, and "already a member" counts as success. Removes go 20 per $batch; a 404 counts as removed, other failures are retried one by one. Retries: 429, 503, 504 and Exchange throttling messages, Retry-After honoured (capped at 120 s), otherwise 2, 4, 8, 16 s, five attempts. Exchange groups are found by their Entra object ID and addressed by their Exchange GUID; a new Exchange group is created with join and leave closed.
- **Run (step 1.6):** the run lock is a lease of 2 × tick; an expired lease is taken over with an ETag check, so two jobs can't both win, and a crashed job can't release its successor's lock. Precisions:
  - due: enabled, and a newer sync-now request, or never run, or the interval is over (one minute tolerance, at least one tick); SyncNow mode only handles requests or the one named definition;
  - users are read once with the fields of all rules; definitions of the other runbook are evaluated only when a rule references their group;
  - a group the engine creates gets its ID stored at once, before members are written, so a crash can't create it twice; the first fill skips the change limit;
  - the marker is set on a group's first write; renaming on adopt adds prefix and suffix only if missing;
  - status is written for every due definition; a run record only when something changed, warned, failed, ran dry or waited for approval; a skipped tick or a pause writes one system record;
  - the job fails when any definition ended Blocked or Error; the heartbeat is written at the end of every run that got the lock.
- **For the web app (Phase 4):** Get-DgDirectoryObjectById reads users and groups by ID through directoryObjects/getByIds (1,000 per call) so the API can name included, excluded and compare objects. tools/Export-RuleProperties.ps1 writes the property map's names and types to src/Web/src/rules/properties.json for the editor's autocomplete; a Pester test fails when that file is out of date.

## Later versions

- Custom names for extensionAttribute1–15 (e.g. `user.costCenter` instead of `user.extensionAttribute7`), defined in Settings and offered in the rule editor. Not in the MVP.
