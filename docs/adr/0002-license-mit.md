# ADR 0002: License RDG under the MIT License

| | |
| --- | --- |
| Status | Accepted |
| Date | 2026-11-08 |
| Decider | RuminahuiM |

## Context

RDG is published as an open source project. Without a license, nobody may legally use, copy or modify the code, even though the repository is public. RDG is meant to be used by organisations in their own Microsoft 365 tenants, often adapted to local needs, and it should be easy for others to contribute.

RDG was built by its author in his own time. The author holds the copyright.

## Decision drivers

- Low barrier for organisations that want to install and adapt RDG
- Simple obligations that IT teams understand without legal review
- Compatible with the licenses of the bundled dependencies
- Common in the PowerShell and Microsoft 365 ecosystem

## Considered options

1. **MIT License**
2. **Apache License 2.0**
3. **GNU GPL v3.0**

| Criterion | MIT | Apache-2.0 | GPL-3.0 |
| --- | --- | --- | --- |
| Obligations for users | keep copyright and license notice | keep notices, mark changed files, include NOTICE if present | release source of distributed changes under GPL |
| Explicit patent grant | no | yes | yes |
| Organisations may adapt RDG internally without publishing changes | yes | yes | yes (obligations apply on distribution) |
| Usage in the ecosystem | very common (PowerShell, Microsoft Graph SDKs) | common | rare |
| Compatible with bundled dependencies (web app: 116 MIT, 1 Apache-2.0, 1 0BSD) | yes | yes | yes |

## Decision

Option 1: RDG is licensed under the MIT License, copyright held by the author.

## Consequences

**Positive**

- The shortest and best known license, easy to accept for organisations.
- Contributions are accepted under the same license (inbound equals outbound), stated in `CONTRIBUTING.md`.

**Negative**

- No explicit patent grant. For a tool like RDG this risk is considered low.
- Others may build closed-source derivatives. This is accepted; the goal is wide use, not reciprocity.

## Links

- [Choose a License: MIT](https://choosealicense.com/licenses/mit/)
- [credativ: Understanding open source licenses, GPL, MIT and Apache compared](https://www.credativ.de/en/blog/credativ-inside/understanding-open-source-licenses-gpl-mit-apache-compared/)
