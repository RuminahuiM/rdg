# RDG – Real Dynamic Groups

Rule-based membership for Microsoft 365 groups of any type: Security, Microsoft 365, mail-enabled security groups and distribution lists. You write a rule in Entra dynamic-group syntax; RDG evaluates it on a schedule and keeps the group's members in sync as ordinary static members, so the group works everywhere a static group does (for example as recipients in Defender preset policies).

> **Status:** private, pre-release. Not ready for use. Name is temporary.

## How it works

- **Engine** (PowerShell, Azure Automation runbooks) evaluates the rules and writes members through Microsoft Graph and Exchange Online.
- **Web app** (React, Azure Static Web Apps) and **API** (Azure Functions) let IT staff manage definitions, see activity and approve large changes.
- **Cosmos DB** stores definitions, status, runs and audit.
- **OpenTofu** deploys everything from the adopter's own Azure DevOps.

Design and plan: see [docs/](docs/README.md). Working rules: [CONTRIBUTING.md](CONTRIBUTING.md).

## Repository layout

| Folder | Contents |
|---|---|
| `src/DgEngine/` | Engine module: tokenizer, parser, evaluator, sync. Shared by runbooks and API |
| `src/Runbooks/` | Runbook entry scripts |
| `src/Api/` | Azure Functions app |
| `src/Web/` | Web app |
| `infra/` | OpenTofu configuration |
| `bootstrap/` | One-time setup scripts for Azure and the tenant |
| `deploy/` | Azure DevOps pipeline template and deploy script for adopters |
| `tests/` | Pester tests and the rule conformance suite |
| `tools/` | Developer scripts (lint, build) |
| `docs/` | Links to the design, operator docs later |
