# Story-Lifecycle (verbindlich, Implementation-Chat)

Status im Tracking-Tool: **To Do, In Progress, In Review, Done**. Mapping je Tool siehe `../conventions/tracking_adapter.md`.

## Die 12 Schritte

| Nr. | Schritt | Detail |
|---|---|---|
| 1 | Task-Analyse | Story vollständig ziehen: Beschreibung, AC, DoD, Labels, Sprint, Links. Scope verstehen, bevor etwas getippt wird. |
| 2 | Start-Checkliste | `story_start_checklist.md` (Blocker, Findings, Risiken, Vor-Story). |
| 3 | WebSearch | Best Practices der Story-Domain mit aktuellem Jahr. Stichworte siehe `../tech_profile.md`. |
| 3b | ADR-Check | Relevante Accepted-ADRs einhalten. Entsteht eine ADR-würdige Entscheidung (Trigger in `adr_workflow.md`), zuerst ADR als Proposed vorschlagen und entscheiden lassen, dann umsetzen. |
| 4 | Senior-Decision-Fragen | 1 bis 3 Fragen per AskUserQuestion bei jeder Story mit Entscheidungsspielraum. Pflicht bei M/L, bei API-Änderungen, neuen Schnittstellen oder Cross-Story-Impact. Typische Themen: Defaults vs. Edge-Cases, darf Done-Code angefasst werden, Test-Strategie (Mocks vs. echte Services), Library-Wahl. |
| 5 | Status In Progress | Sobald das Coding beginnt. |
| 6 | Umsetzung | Code, Tests, Doku. Bei mehrstufigen Umsetzungen vor jedem nicht-trivialen Schritt kurz nachfragen. |
| 7 | Verifikation | Volle Test-Suite (nicht nur Story-Tests), Lint, Format, Typecheck, Syntax-/Truncation-Check gemäss `../tech_profile.md`. Bei Container-/Deployment-Stories echter Build plus Smoke-Test auf der Zielumgebung, nicht nur Sandbox. |
| 8 | Closing-Review | `closing_review.md`, Phase 1 und 2 vollständig, auch bei S-Stories. |
| 9 | Findings vorstellen | Liste mit Optionen A (jetzt fixen), B (Polish/später mit Trigger), C (bewusste Projekt-Limitation). |
| 10 | Status In Review | Plus Frage an User "OK für Done?" mit klaren Optionen. |
| 11 | Explizites User-OK abwarten | Harte Regel. "War ja eh ok" reicht nicht. Bei Unsicherheit nachfragen. |
| 12 | Done-Flow | `done_flow.md`: Worklog, Status Done, Done-Kommentar, Evidence-File, Git-Commit, Demo-Check. |

## Warum diese Reihenfolge

Schritte 3 und 4 werden am häufigsten "vergessen". Kommen WebSearch und User-Input vor der Umsetzung, vermeidet das falsche Defaults, Code-Roundtrips wegen falsch verstandener Anforderungen und Tooling-Desaster ohne Klärung.

## Sonderregeln

- **Abweichung von einem Accepted-ADR:** Nie stillschweigend. Rückfrage, dann entweder ADR einhalten oder neues ADR, das das alte ersetzt.
- **Done-Story-Code ändern:** Merkt Claude beim Umsetzen, dass eine bereits abgeschlossene Story erweitert werden muss, NICHT stillschweigend tun. Erst fragen (in dieser Story oder als eigene Refactor-Story), dann als Finding tracken und in der ursprünglichen Evidence einen Nachtrag vorsehen.
- **Zu frühes Done:** Falls versehentlich auf Done gesetzt, zurück auf In Review, Review nachholen, dann mit User-OK wieder auf Done.
- **Selbst-Audit:** Fragt der User "hast du sauber gearbeitet?", ehrlich auditieren, Schwachstellen auflisten, Findings ergänzen, Optionen anbieten. Nie "alles sauber" ohne echten Audit.
