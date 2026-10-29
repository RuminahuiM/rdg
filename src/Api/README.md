# API

Azure Functions app (PowerShell 7.4), linked to the Static Web App. Contract: `openapi.yaml`.

- One folder per route; every `run.ps1` is identical. The route in `function.json` is the OpenAPI path, so `Modules/DgApi` finds the operation and its roles in the contract.
- `Modules/DgApi`: request handling, roles, problems, audit, one handler per operation. `openapi.json` there is generated: run `npm run api:export` after changing `openapi.yaml`.
- The engine (`src/DgEngine`) does the work: store, Graph, rule checks, preview.

Run locally:

- Without Azure or Core Tools: `./tools/Start-ApiLocal.ps1 -Role admin`, then open http://localhost:7071/api/me. In-memory store, invented tenant.
- With Azure Functions Core Tools: `./tools/Build-ApiPackage.ps1 -Local`, copy `local.settings.example.json` to `local.settings.json` and fill it in, then `func start` in `src/Api`.

Package: `./tools/Build-ApiPackage.ps1` writes `out/api-<version>.zip`. Tests: `tests/Api`.
