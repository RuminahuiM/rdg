# Schemas

JSON Schema (draft 2020-12) for every document type RDG stores in Cosmos DB. They are the contract between the API (writes `config`) and the engine (writes `state` and `runs`); see the Data Model design.

| File | Container | `type` | Partition key |
|---|---|---|---|
| `cosmos/definition.schema.json` | config | definition | its own ID |
| `cosmos/settings.schema.json` | config | settings | `settings` |
| `cosmos/audit.schema.json` | config | audit | definition ID or `settings` |
| `cosmos/status.schema.json` | state | status | definition ID |
| `cosmos/lock.schema.json` | state | lock | `lock` |
| `cosmos/heartbeat.schema.json` | state | heartbeat | `system` |
| `cosmos/run.schema.json` | runs | run | definition ID or `system` |
| `cosmos/schema-marker.schema.json` | each | schema | `system` |

Rules:

- Writers are strict: whatever a component writes must validate. Readers are tolerant (see "Schema versions and upgrades" in the Data Model design).
- A breaking change bumps `schemaVersion` and adds a new schema version next to the old one for one release.
- Valid examples live in `tests/Fixtures/cosmos/` and are checked by `npm run contracts:check`.

The HTTP contract is `src/Api/openapi.yaml`.
