# CLAUDE.md: Einstieg für Claude

Diese Datei ist der verbindliche Einstieg. Sie verweist auf das Regelwerk unter `harness/`. Bei Widerspruch gilt: aktuelle Anweisung des Users > `harness/`-Dateien > eigene Gewohnheiten.

## 1. Kontext

- Solo-Semesterarbeit an der TBZ (HF). User übernimmt Product Owner, Scrum Master und Entwickler; Claude unterstützt je nach Chat-Rolle.
- Projekt-Stammdaten (Titel, Abgabe, Mentor-Termine, Arbeitsrhythmus, Tracking-Tool, Issue-Prefix) stehen in `docs/00_projekt_steckbrief.md`. Immer dort nachschlagen, nie raten.
- Der konkrete Tech-Stack und die Stack-spezifischen Prüfungen stehen in `harness/tech_profile.md`.
- Thema dieser Arbeit (Semester 4, ITCNE25): RDG (Real Dynamic Groups) als DevOps-Projekt aufnehmen und eine KI-Maintainer-Pipeline bauen. Hintergrund zu RDG: Claude-Projekt-Doc `claude/00-projekt-briefing.md`, Entscheide: `claude/02-entscheide-semesterarbeit.md`.

### 1.1 Scope der Semesterarbeit (Stand 21.10.2026)

| In Scope (Semesterarbeit) | Out of Scope |
|---|---|
| RDG als DevOps-Projekt aufnehmen: Repo, Prozesse, Standards, Testing, Doku | Funktionale Weiterentwicklung des Tools selbst |
| Alle Pipelines (CI, Release, Deploy), auch die schon vorhandenen, weil sie bisher nicht richtig getestet sind | Read-write-Test und kleine Anpassungen am Tool, die der User vor Beginn der Arbeit selbst abschliesst |
| KI-Maintainer-Pipeline (später in der Arbeit) | |

### 1.2 Ordnerstruktur

| Ordner | Inhalt | Wo |
|---|---|---|
| `00_RDG/` (Root, dieser Harness) | Hauptumgebung von Claude: Regeln, Semester-Management, Sprint Journal, Bericht, Präsentation | Lokal auf dem PC. Nie ins öffentliche RDG-Repo; der Teil für die Experten geht ins private Semester-Repo |
| `00_RDG/RDG_Base/` | Bisheriger RDG-Code (MVP). Wird in ein GitHub-Repo überführt (nach dem Kickoff) | Danach GitHub, später öffentlich (Open Source) |
| Zweites, privates GitHub-Repo (Name im Kickoff) | Semester-Doku für die Experten: Steckbrief, Sprint Journal, Evidence, Risk Register, Mentor-Termine, Bericht, Präsentation | Privat, Experten als Collaborators. Erfüllt die Vorgabe "Experten haben jederzeit Zugriff" (Merkblatt A-4) |

### 1.3 Was wohin gehört

- **Ins Projekt-Repo (RDG):** alles, was zum Tool gehört und an das Projekt gebunden ist, auch die Projekt-Doku (Requirements, Design, Architekturentscheidungen, Tech-Stack, Guides), Pipelines, Tests, Standards. Issues und Backlog in GitHub.
- **Ins private Semester-Repo:** die Semester-Doku, die die Experten sehen sollen (Abgrenzung zum rein lokalen Harness wird im Kickoff, Block E, festgelegt).
- **Im Harness (lokal):** alles, was nur die Semesterarbeit betrifft: Steckbrief, Scrum-Setup, Risk Register, Findings, Traceability, Quellen, Sprint Journal, Evidence, Mentor-Termine, Bericht, Präsentation, TBZ-Unterlagen.
- Harness-Templates unter `docs/` für projektgebundene Inhalte (z.B. `05_requirements.md`, `06_tech_stack.md`, `07_design.md`, `adr/`) sind nur Vorlagen. Die echten Dokumente entstehen im Repo; im Harness wird darauf verlinkt.
- Der KI-Maintainer bekommt später ein eigenes Regelwerk im Repo. Harness-Regeln gelten nicht automatisch für ihn.

## 2. Chat-Rollen

| Rolle | Datei | Kurz |
|---|---|---|
| Strategie-Chat | `harness/roles/strategie_chat.md` | Co-SM / Co-Projektleitung: Planning, Daily Journal, Review, Retro, Risiken, Mentor-Kommunikation |
| Implementation-Chat | `harness/roles/implementation_chat.md` | Senior Engineer: Stories umsetzen, Closing-Review, Done-Flow |
| Doku-Chat | `harness/roles/doku_chat.md` | Schlussbericht Abschnitt für Abschnitt, Glossar-Pflege |

Rolle unklar? Fragen, bevor gearbeitet wird.

## 3. Harte Regeln (gelten in allen Rollen)

1. **Verständnisfragen zuerst:** Vor nicht-trivialer Arbeit 1 bis 3 gezielte Fragen (AskUserQuestion), siehe `harness/workflows/story_lifecycle.md`.
2. **WebSearch vor technischen Empfehlungen**, mit aktuellem Jahr im Suchbegriff.
3. **Kein Done ohne explizites User-OK.** Status-Workflow: To Do, In Progress, In Review, Done (`harness/conventions/tracking_adapter.md`).
4. **Jedes Finding wird getrackt** (`docs/13_deferred_findings.md`), nicht nur im Chat oder im Evidence-File erwähnt.
5. **Done-Code nicht stillschweigend ändern.** Erst fragen, dann als Finding tracken.
6. **Ehrlicher Selbst-Audit:** "Hast du sauber gearbeitet?" ist nie rhetorisch. Schwachstellen offen benennen.
7. **Schreibstil:** Deutsch mit englischen Fachbegriffen, keine Em-Dashes, keine Icons, Datum TT.MM.JJJJ (`harness/conventions/writing_style.md`).
8. **Tooling-Schutz:** Nach Edits an Dateien über 150 Zeilen Zeilenzahl und Syntax prüfen; grosse Rewrites per Script statt Edit-Tool (`harness/conventions/tooling_safeguards.md`).
9. **Git:** Nur selbst angefasste Files committen, nie direkt pushen, nie `.git/index` manipulieren. Branching- und Merge-Strategie werden im Projekt festgelegt (`harness/conventions/git.md`).
10. **Session-Summaries inline im Chat**, nie als Repo-File.
11. **Daily Journal nur auf explizite Anweisung** des Users aktualisieren.
12. **ADRs laufend führen:** Architektur-Entscheidungen bei Trigger sofort als ADR vorschlagen (Proposed), Accepted nur mit User-OK, Accepted-ADRs einhalten und nicht umschreiben (`harness/workflows/adr_workflow.md`).
13. **Trennung Repo und Harness:** Der Harness bleibt lokal. Ins RDG-Repo nie Sprint Journal, Mentor-Protokolle, Bericht, HEKS-Interna, echte Tenant-Daten oder Secrets. Interne RDG-Dokumente bleiben in `docs/internal/` (per `.gitignore` ausgeschlossen).
14. **Kein Schreiben in produktive Tenants:** Tests laufen im eigenen Test-Tenant. Nichts im HEKS-Tenant ändern ohne ausdrückliche Anweisung.

## 4. Wo liegt was

| Thema | Pfad |
|---|---|
| Kickoff-Checkliste | `harness/00_kickoff.md` |
| Story-Ablauf (12 Schritte) | `harness/workflows/story_lifecycle.md` |
| Story-Start-Checkliste | `harness/workflows/story_start_checklist.md` |
| Closing-Review (8 Phasen, 10 Kategorien) | `harness/workflows/closing_review.md` |
| Done-Flow (Kommentar, Evidence, Zeit, Commit) | `harness/workflows/done_flow.md` |
| Demos | `harness/workflows/demo_convention.md` |
| ADRs (Trigger, Lebenszyklus, Verlinkung) | `harness/workflows/adr_workflow.md`, Ablage `docs/adr/` |
| Scrum-Events und Mentor-Termine | `harness/workflows/sprint_events.md` |
| Doku-Abschnitts-Flow | `harness/workflows/doku_abschnitt_flow.md` |
| IDs und Dateinamen | `harness/conventions/ids_and_naming.md` |
| Tracking-Tool-Mapping | `harness/conventions/tracking_adapter.md` |
| Tech-Profil | `harness/tech_profile.md` |
| Projekt-Dokumente | `docs/` |
| Sprint-Ablage und Templates | `sprint_journal/` |
| TBZ-Vorgaben, Bewertungsraster | `tbz_resources/` |

## 5. Harness pflegen

Etabliert sich während des Projekts eine neue dauerhafte Regel (z.B. nach einem Fehler), wird sie in der passenden Harness-Datei ergänzt, mit Datum und einer Zeile "Warum". Kurz im Chat bestätigen, welche Datei geändert wurde.

### Änderungslog

| Datum | Datei | Änderung | Warum |
|---|---|---|---|
| 21.10.2026 | `CLAUDE.md`, `harness/conventions/git.md`, `harness/conventions/tooling_safeguards.md`, `harness/conventions/writing_style.md`, `harness/tech_profile.md`, `PROJECT_INSTRUCTIONS.md`, `tbz_resources/README.md` | Harness auf RDG (Semester 4) adaptiert | Neues Projekt: PowerShell/React/OpenTofu-Stack, GitHub Flow mit PRs statt lokaler Commits, öffentliches Produkt-Repo, KI-Maintainer als zweite Ebene |
| 21.10.2026 | ganzer Harness | Inhalt von `SemHarness/` in den Root `00_RDG/` verschoben; Scope und Ablage-Regeln ergänzt; Git-Strategie offen gelassen; Tracking GitHub | Harness ist die Hauptumgebung von Claude; Projekt-Entscheide (Branching, Doku) gehören ins Projekt selbst |
| 21.10.2026 | `CLAUDE.md`, `harness/conventions/git.md` | Zweites, privates Repo für die Semester-Doku ergänzt | Experten brauchen jederzeit Zugriff; Semesterarbeit soll sich nicht mit dem Open-Source-Tool mischen |
