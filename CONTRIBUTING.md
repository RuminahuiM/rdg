# Contributing

Working rules for RDG. Short on purpose: if something isn't covered here, follow the existing code, and if that doesn't help, decide and add the rule here.

## Workflow

- Work follows the [implementation plan](docs/README.md): one step at a time, reviewed before the next one starts.
- Branches: `main` is always releasable. Work branches are `step/<number>-<slug>`, for example `step/1.1-parser`, or `fix/<slug>` for fixes outside a step.
- Commits use [Conventional Commits](https://www.conventionalcommits.org/) with the area as scope and the step in brackets:
  - `feat(engine): parse -in and -notIn operators [1.1]`
  - `fix(api): return 412 on stale ETag [3.2]`
  - `docs: add settings reference [7.1]`
  - Scopes: `engine`, `runbooks`, `api`, `web`, `infra`, `bootstrap`, `deploy`, `ci`, `docs`.
- A change that departs from the design updates the design doc in the same step. The design docs are the source of truth; the code must not quietly disagree with them.
- Everything is in English: code, comments, docs, commit messages.

## Never commit

- Secrets of any kind: keys, tokens, connection strings, certificates, passwords. RDG uses managed identities and federation; there should be nothing to commit.
- Real settings files (`*.tfvars` outside `examples/`), state files, `local.settings.json`, `.env`.
- Real tenant data: user names, UPNs, group names or IDs from HEKS or any other tenant. Tests and examples use invented data (`contoso.org`, `alex.example@contoso.org`).

## PowerShell

Applies to `src/DgEngine`, `src/Runbooks`, `src/Api`, `bootstrap`, `deploy` and `tools`.

**Basics**

- PowerShell 7.4. `#Requires -Version 7.4` at the top of every script.
- Lint must pass: `./tools/Invoke-Lint.ps1` (same as CI). VS Code formats on save with matching settings.
- 4 spaces, opening brace on the same line (OTBS), no aliases (`Where-Object`, not `?`), full parameter names.
- `Set-StrictMode -Version Latest` in every module and script.
- Never `Invoke-Expression`, never build code from strings, never `Add-Type` with inline C#.

**Naming**

- Functions use approved verbs (`Get-Verb`) and a prefix: `Dg` in the engine module (`ConvertTo-DgRuleAst`, `Get-DgDiff`), `Rdg` in scripts adopters run (`Initialize-RdgAzure.ps1`).
- Variables and parameters in camelCase inside functions (`$changeLimit`), PascalCase for parameters (`-ChangeLimit`).
- Files are named after the function they contain: `Public/Get-DgDiff.ps1`.

**Module layout (DgEngine)**

```
src/DgEngine/
  DgEngine.psd1        manifest, explicit FunctionsToExport (no wildcards)
  DgEngine.psm1        dot-sources Private/ (recursively) then Public/
  Public/              one exported function per file
  Private/
    Rules/             tokenizer, parser, validator, property map
    Evaluate/          evaluator, group resolver, implicit filters
    Sync/              diff, safety brakes, run orchestration, run records
    Writers/           Graph and Exchange adapters (users, groups, members, recipients)
    Store/             Cosmos DB client, in-memory store, run lock
    Connect/           managed identity: Graph, Exchange, tokens
    Certificate/       Key Vault reads for the sign-in certificate renewal
src/Runbooks/          runbook sources; tools/Build-Runbook.ps1 inlines DgEngine into each
src/Api/               Function App: one folder per route, Modules/DgApi with one handler per operation
src/Web/               web app: React + Vite; see src/Web/README.md
```

The areas match the Engine design. One helper per file inside them.

- No PowerShell classes. The runbook build inlines the module into one file, and classes don't reload cleanly. Use `[pscustomobject]` with a `PSTypeName` instead (`PSTypeName = 'Dg.RuleNode'`).
- Every public function has `[CmdletBinding()]`, typed parameters with validation attributes, `[OutputType()]` and comment-based help with at least one example.

**Errors and output**

- Public functions report failures with `$PSCmdlet.ThrowTerminatingError()` and a clear message; helpers `throw`. Entry scripts (runbooks, bootstrap) set `$ErrorActionPreference = 'Stop'`.
- No `Write-Host`. Results go to the pipeline; progress to `Write-Verbose`; notable events to `Write-Information`; problems to `Write-Warning` or errors.
- Graph and Exchange are called only through the directory adapters (step 1.5), never directly from engine logic. That keeps everything testable without a tenant.
- Never log secrets or tokens. User principal names and display names may appear in run records and logs, nothing more personal.

## Tests

- Pester 5. Tests live in `tests/<Area>/`, mirroring the source: `tests/DgEngine/Sync/Get-DgDiff.Tests.ps1`, `tests/Api/...`.
- Shared test data (invented users and groups) lives in `tests/Fixtures/`.
- Bootstrap helpers live in `bootstrap/RdgBootstrap.psm1`, tested in `tests/Bootstrap/`. Functions that call Graph take the call as an `-Invoke` script block, so tests need no tenant; the scripts themselves stay thin.
- Deploy helpers (`deploy/RdgDeploy.psm1`) are tested the same way in `tests/Deploy/`; `tests/Tools/` builds a release bundle and checks its layout and version stamp.
- Unit tests mock the directory and store adapters; they never need a tenant or Azure.
- Every bug fix comes with a test that fails without the fix.
- Rule behaviour is tested through the conformance suite in `tests/rules/` (format defined in step 1.1), so a rule case is data, not code. Rules taken from a real tenant are added with the same structure but invented values.
- Target: 80 % line coverage on DgEngine.

## TypeScript and the web app

Applies to `src/Web`.

- TypeScript `strict`, no `any` (use `unknown` and narrow), no non-null `!` without a comment saying why.
- ESLint and Prettier must pass; Prettier decides formatting, not reviewers.
- Components are function components with PascalCase file names (`GroupList.tsx`), one main component per file named after it. Small helpers used only there, or a few tiny variants of one thing (the badges, the error screens), may share the file. Hooks start with `use`.
- API types come only from the types generated from `openapi.yaml`. No hand-written copies of API shapes.
- Server data goes through TanStack Query; local UI state stays in components. No global store unless a real need shows up.
- Use Fluent UI v9 components and tokens; no custom colours or fonts outside the theme. The rule editor's syntax colours are the one exception (light and dark pairs in `RuleEditor.tsx`).
- Every user-facing text is in `src/strings/en.ts`.
- Tests with Vitest and Testing Library, against the mock API (`src/mocks`, MSW); end-to-end flows with Playwright against the mock build. The mock follows the contract (roles, ETags, problems), so a test that passes against it shows the app handles the real answers.

## OpenTofu

Applies to `infra/`.

- `tofu fmt` formatting; TFLint must pass.
- snake_case for resources, variables and outputs. Resource names in code describe the role (`azurerm_cosmosdb_account.main`), Azure names follow the pattern in the Infrastructure doc.
- Every variable has `description`, `type` and, where it makes sense, a `validation` block and a default.
- Modules don't configure providers or backends; only the root does.
- Data resources (Cosmos DB, Key Vaults) carry `prevent_destroy`. Renames use `moved` blocks.
- `tofu test -var-file=../examples/contoso.tfvars` (`infra/tests`, mocked provider, no Azure) must pass. Assert on outputs, not on module internals.
- Trivy runs on `infra/`. An accepted finding gets `#trivy:ignore:<id>` above the resource, with the reason in the comment.

## Data and APIs

- JSON property names in camelCase, in Cosmos DB documents and in the API alike.
- Times are UTC and ISO 8601 (`2026-10-09T19:42:14Z`) everywhere; the web app converts for display.
- IDs of Entra objects are stored as the object ID (GUID), never as a display name.
- `openapi.yaml` and the JSON schemas in step 0.3 are the contracts. Change the contract first, then the code.

## Versions

- Semantic Versioning for releases (`v1.2.0`).
- Dependencies are pinned to exact versions (npm lock file, OpenTofu lock file, PowerShell module versions in one place). Renovate proposes updates.
