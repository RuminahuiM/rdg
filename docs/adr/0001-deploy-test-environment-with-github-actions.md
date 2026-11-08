# ADR 0001: Deploy the test environment with GitHub Actions

| | |
| --- | --- |
| Status | Proposed |
| Date | 2026-11-08 |
| Decider | RuminahuiM |

## Context

Every merge to `main` shall be deployed automatically to a test environment, and a release shall only be published after a manual approval. RDG already ships an Azure DevOps pipeline (`deploy/azure-pipelines.yml`) for adopters who install RDG in their own tenant. The project itself lives on GitHub: code, issues, CI (`.github/workflows/ci.yml`), release workflow and, later, an AI maintainer that works on GitHub issues.

The question is which platform runs the deployment to the project's own test environment.

## Decision drivers

- One place to see the whole flow from issue to release
- No long-lived Azure credentials stored in the pipeline
- Manual approval gate before a release
- Free for this project
- The existing Azure DevOps path for adopters must keep working

## Considered options

1. **GitHub Actions** with `azure/login` and OpenID Connect (workload identity federation)
2. **Azure DevOps Pipelines** with a workload identity federation service connection
3. Keep deploying manually from a workstation

## Decision

Option 1: GitHub Actions deploys the test environment.

| Criterion | GitHub Actions | Azure DevOps | Manual |
| --- | --- | --- | --- |
| Same platform as code, CI, issues and AI maintainer | yes | no, second platform | no |
| Login without stored secrets | yes, OIDC | yes, workload identity federation | no, interactive login |
| Manual approval before release | environments with required reviewers | environments with approvals | by hand only |
| Cost for this project | free for public repositories | free grant: 1 Microsoft-hosted job, 1,800 min per month, requires a linked Azure subscription for billing | free |
| Repeatable, independent of a workstation | yes | yes | no |

## Consequences

**Positive**

- Issue, pull request, CI, deployment and release are visible in one place.
- No client secret has to be stored or rotated.
- Approvals use GitHub environments, the same mechanism as the release gate.

**Negative**

- The Azure DevOps pipeline for adopters is no longer exercised by the project's own deployments. It must be checked separately before a release.
- The federated credential depends on the subject claim format. Repositories created after 2026-07-15 use an immutable default `sub` claim that includes owner and repository IDs, so the credential must match that format.
- Environment protection rules and branch restrictions must be configured carefully, so that only `main` can request a token for the test environment.

## Links

- [GitHub Docs: Configuring OpenID Connect in Azure](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure)
- [Microsoft Learn: Configure and pay for parallel jobs](https://learn.microsoft.com/azure/devops/pipelines/licensing/concurrent-jobs)
