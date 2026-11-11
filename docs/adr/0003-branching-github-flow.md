# ADR 0003: Use GitHub Flow for branching

| | |
| --- | --- |
| Status | Proposed |
| Date | 2026-11-11 |
| Decider | RuminahuiM |

## Context

RDG is maintained by one person and later also by an AI agent that opens pull requests. Every change should follow the same path, so that CI, review and release work the same way no matter who made the change. Releases are cut from tags (`vMAJOR.MINOR.PATCH`, see `release.yml`); installations deploy published releases only, so `main` does not have to be deployed on every merge.

## Decision drivers

- One simple path for every change, human or agent
- Every change is checked by CI and reviewed before it reaches `main`
- Little overhead for a one-maintainer project
- Fits the existing tag-based release workflow

## Considered options

1. **GitHub Flow:** short-lived branches from `main`, merged back through a pull request
2. **Git Flow:** long-lived `develop` and `main`, plus feature, release and hotfix branches
3. **Trunk-based development:** commits go to `main` directly or through very short branches, often behind feature flags

| Criterion | GitHub Flow | Git Flow | Trunk-based |
| --- | --- | --- | --- |
| Every change goes through a pull request with CI | yes | yes | not necessarily |
| Long-lived branches to keep in sync | none | `develop` and release branches | none |
| Fits a small project with one maintainer | yes | heavy | yes |
| Agent changes can be gated by review | yes, by the pull request | yes | weak without pull requests |
| Fits tag-based releases from `main` | yes | releases come from release branches | yes |

## Decision

Option 1: RDG uses GitHub Flow.

- `main` is always releasable and only changes through pull requests.
- Work happens on short-lived branches named `<type>/<short-slug>` (see `CONTRIBUTING.md`).
- A pull request is merged when CI is green and the maintainer has reviewed it. Pull requests from the AI agent are always reviewed and merged by the maintainer.
- Releases are tags on `main`; there are no release branches.
- Merged branches are deleted automatically.

## Consequences

**Positive**

- One rule for everyone, easy to explain and to enforce with a branch ruleset (story CI-5).
- The pull request is the natural gate for the AI agent.

**Negative**

- No place to stabilise a release apart from `main`. If that is ever needed, a pre-release tag (`v1.2.0-rc.1`) is used first.
- With a single maintainer, review means self-review for own changes. CI is the main safety net.

## Links

- [GitHub Docs: GitHub flow](https://docs.github.com/en/get-started/using-github/github-flow)
- [Trunk Based Development](https://trunkbaseddevelopment.com/)
- [Vincent Driessen: A successful Git branching model (Git Flow)](https://nvie.com/posts/a-successful-git-branching-model/)
