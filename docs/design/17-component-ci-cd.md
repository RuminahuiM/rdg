# Component Design: CI/CD

Oct 9, 2026 · @Dodoe

CI/CD covers the repository and the Azure DevOps pipelines that test, package and deploy the tool. Part of Doc.

## Overview

Two sides, kept apart on purpose:

| Side | Where | Who runs it | What it does |
| --- | --- | --- | --- |
| **Project** | Public GitHub repo, GitHub Actions | RDG maintainers | Tests every change; builds and publishes a release bundle for each version tag |
| **Installation** | Adopter's own Azure DevOps project | Each adopter (HEKS first) | Downloads one release bundle, checks it, and deploys it with their settings file |

Adopters never build RDG and never need access to the project repo. One number, the RDG version, decides what runs in their tenant.

## Principles

- **One version, two steps.** OpenTofu deploys infrastructure; the pipeline then deploys the code of the same version. That is the common practice: OpenTofu state stays small and holds no code, code-only releases don't produce noisy plans, and each step can be rerun on its own.
- **Built once, deployed many times.** The release bundle is built by the project; installations only deploy it. Same bytes in every tenant.
- **No secrets stored.** The pipeline signs in with workload identity federation. The one token Static Web Apps needs for an upload is fetched at run time and never saved.
- **A person approves every apply** in the MVP.

## Project repository

```
rdg/
  src/
    DgEngine/          PowerShell module: tokenizer, parser, evaluator, sync (shared)
    Runbooks/          Sync-EntraGroups.ps1, Sync-ExchangeGroups.ps1, Renew-SignInCertificate.ps1
    Api/               Function App (see API)
    Web/               React app (see Web App)
  infra/               OpenTofu (see Infrastructure)
  bootstrap/           Initialize-RdgAzure.ps1, Initialize-RdgTenant.ps1, New-RdgTestUsers.ps1
  deploy/
    azure-pipelines.yml   template the adopter copies
    Deploy-Rdg.ps1        steps the pipeline calls (kept out of YAML so they can be tested)
  tests/
    rules/             conformance cases: rule, user, expected result
  docs/
  tools/               Invoke-Lint.ps1, build scripts (same commands locally and in CI)
  .github/workflows/   ci.yml, release.yml (+ pull_request_template.md)
  renovate.json
```

## Project CI (ci.yml)

Runs on every pull request and on `main`. A pull request can only merge when all jobs pass.

| Job | Checks |
| --- | --- |
| powershell | PSScriptAnalyzer (repo rules); Pester for DgEngine, the API, the runbook entry points, bootstrap, deploy and tools, with 80 % line coverage on DgEngine; a release bundle build (without the web app) so release.yml can't break unnoticed |
| rules | The conformance suite: every operator, property type and edge case from the Engine doc, as data files. A rule change without a matching case fails review |
| web | `tsc --noEmit`, ESLint, Vitest, `vite build`; the generated API types must match `openapi.yaml` (no drift) |
| infra | `tofu fmt -check`, `tofu validate`, TFLint with the azurerm rules, `tofu test` (plans the example settings with a mocked provider) |
| security | Trivy config scan on `infra/` (accepted findings marked inline); `npm audit` of the web app's runtime dependencies (high and above) |

Tests need no tenant: Graph and Exchange calls go through a thin adapter that Pester mocks.

## Release (release.yml)

Runs when a maintainer pushes a tag `vMAJOR.MINOR.PATCH`.

1. Runs the full CI again on the tagged commit.
2. Builds:
   - **Runbooks**: each runbook as one file with DgEngine inlined. Automation then needs no custom module package, and the engine version can't drift from the runbook.
   - **API package**: `api.zip` with DgEngine in `Modules/`, the same build as the runbooks.
   - **Web app**: the `dist/` folder.
   - **infra/**, **bootstrap/** and **deploy/** as they are.
3. Stamps the version into all of them (`/api/health` and every run record report it).
4. Packs `rdg-<version>.zip` (tools/Build-Release.ps1: VERSION, runbooks/, api/api.zip, web/, infra/, bootstrap/, deploy/, examples/), writes `SHA256SUMS`, and adds a GitHub build provenance attestation (`actions/attest`).
5. Creates a **draft** GitHub release from `.github/release-notes.md`. A maintainer completes the notes, which always state breaking changes, whether stage 2 must be rerun (new tenant grants) and whether the settings file needs new values, then publishes it. Tags with a prerelease part are marked as prereleases.

Release candidates (`v1.2.0-rc.1`) go through the same steps and are deployed to the test tenant first.

## Installation repository

What the adopter keeps in Azure DevOps:

```
rdg-deploy/
  azure-pipelines.yml     copied from the release, rarely changes
  settings/
    prod.tfvars           the settings file (see Infrastructure)
```

The RDG version is a pipeline variable `rdgVersion` in `azure-pipelines.yml`. Upgrading is a one-line pull request.

## Deploy pipeline

One pipeline, run manually or on a change to `main`. Stages:

1. **Fetch.** Downloads `rdg-<rdgVersion>.zip` and `SHA256SUMS` from the GitHub release and stops if the checksum or the bundle's `VERSION` doesn't match. OpenTofu is installed from its GitHub release, also checked against its checksums.
2. **Plan.** `tofu init` and `tofu plan` with the settings file. The plan file is encrypted like the state and kept as a pipeline artifact. The run summary lists replaces and deletes on top, and a warning appears when there are any. OpenTofu signs in with the service connection's federation (`ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID`, `SYSTEM_ACCESSTOKEN`, `SYSTEM_OIDCREQUESTURI`), so it gets fresh tokens during long runs.
3. **Approve.** The Apply stage targets the Azure DevOps environment `rdg-<env>`, which has an approval check, an exclusive lock (no two runs at once) and a branch check (`main` only).
4. **Apply.** `tofu apply` of the saved plan. Infrastructure only. Runbooks are created as empty shells on first install (`ignore_changes` on their content), so schedules can link to them.
5. **Deploy code.** Same stage, right after the apply, with the same RDG version:
   - **Runbooks**: the draft of each runbook is replaced with the built file and published (Automation REST API, `draft/content` and `publish`). Unlike `Import-AzAutomationRunbook`, this keeps everything OpenTofu set on the runbook, including its runtime environment.
   - **API**: `api.zip` uploaded to the `packages` container (fixed name, older versions kept by blob versioning), then the Function App is restarted so it loads the new package. `WEBSITE_RUN_FROM_PACKAGE` points at that fixed URL and is set once by OpenTofu.
6. **Web app.** Fills the placeholders in `staticwebapp.config.json` (tenant ID, Key Vault of the sign-in certificate), fetches the Static Web App deployment token through Azure Resource Manager (`listSecrets`) and uploads `web/` with the Static Web Apps CLI (pinned version). The token is passed to the CLI through its environment only and lives only in that step.
7. **Smoke test.** `/api/health` returns the new version; an anonymous call to `/api/definitions` is refused (401, 302 or 403); the published runbooks carry the version. It waits up to 10 minutes for a cold start. A failure marks the run failed.

Rollback: run the pipeline with the previous `rdgVersion`. Data stays; data format changes are always readable by the version before (see Data Model).

**Why the API runs from a package URL.** On the Windows Consumption plan the default is an Azure Files share, and Azure Files only accepts a key-based connection string. Running from a package in blob storage, read with the api identity, removes the share and with it the only key RDG would otherwise need. Trade-offs: no portal editing and no file-system log stream, neither of which RDG uses.

## Dependency updates

Renovate on the project repo, weekly, grouped:

- npm packages (minor and patch grouped, majors one by one)
- OpenTofu providers and the lock file
- PowerShell modules from the PowerShell Gallery (Microsoft.Graph.Authentication, ExchangeOnlineManagement, Pester, PSScriptAnalyzer), via a regex rule: each pinned version has a `# renovate:` comment on the line above
- GitHub Actions, pinned to commit SHAs

Updates reach adopters only through a release. Adopters can let Renovate watch RDG releases and open the one-line version bump, but that's optional.

## Later versions

- Automated end-to-end tests against the test tenant on every release candidate (GitHub Actions with federation to the test tenant).
- Approval only when the plan replaces or deletes something; automatic otherwise.
- Signature check of the bundle in the deploy pipeline, not only the checksum.
- Replace the run-from-package setup with a proper keyless hosting model. Running the API from a blob package only to avoid the Azure Files key is a workaround; candidates are Flex Consumption once it's supported as a linked backend, or a container host.

## Decisions

1. **Developed on GitHub** with GitHub Actions. The repo is created after planning.
2. **A person approves every apply** in the MVP. Implementation goes step by step, with Dodoe verifying each step.
3. **Infrastructure and code deploy in separate steps** of the same pipeline run, with the same version (best practice; see Principles).
4. **Private repo first.** Development starts in a private GitHub repo and goes public later. GitHub Actions on private repos has a monthly minutes allowance, which is plenty for this project; release bundles from a private repo need a token to download, so adopters only use public releases.
5. **The version lives in the DgEngine manifest** (ModuleVersion plus PSData.Prerelease), stamped by the release build into a copy of the sources. Get-DgEngineVersion is exported and is what runbooks, run records and /api/health report, so 1.2.0-rc.1 shows whole everywhere.
6. **Releases start as drafts.** The workflow can't know breaking changes or new grants, so a maintainer writes those notes before publishing.
7. **The pipeline template has no external templates.** Adopters copy one file; everything else runs from the bundle (deploy/Deploy-Rdg.ps1), so the steps always match the RDG version being deployed.
