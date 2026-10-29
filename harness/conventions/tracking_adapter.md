# Tracking-Adapter (tool-agnostisch)

Der Harness spricht von generischen Begriffen. Beim Kickoff wird ein Tool gewählt und unten unter "Projekt-Konfiguration" eingetragen.

## Generische Begriffe

| Begriff | Bedeutung |
|---|---|
| Issue / Story | Arbeitseinheit mit Key, Titel, Beschreibung, AC, Schätzung |
| Status | To Do, In Progress, In Review, Done |
| Blocker-Link | Story A blockiert Story B (`blockedBy` / `blocks`) |
| Done-Kommentar | Strukturierter Abschluss-Kommentar (`../workflows/done_flow.md`) |
| Worklog | Tatsächlich investierte Zeit pro Story |
| Sprint | Zeitbox, der Stories zugeordnet sind |

## Mapping je Tool

| Begriff | Jira | GitHub Issues / Projects | Markdown-only |
|---|---|---|---|
| Story | Issue (Typ Story), Epic als Parent | Issue, Epic als Label oder Parent-Issue | Eintrag in `docs/09_product_backlog.md` |
| Status | Workflow-Transitions (IDs notieren) | Project-Feld "Status" mit den vier Werten | Spalte "Status" im Backlog |
| Blocker-Link | Issue-Link "is blocked by" | "Blocked by #n" im Body oder Sub-Issues | Spalte "Blocked by" |
| Done-Kommentar | Kommentar (Markdown) | Issue-Kommentar, danach Issue schliessen | Abschnitt im Evidence-File |
| Worklog | Worklog-Eintrag (timeSpent) | Kommentar "Zeit: 2h30m" oder Project-Feld | Spalte im Daily Journal und Evidence |
| Sprint | Sprint-Objekt | Iteration-Feld | Spalte "Sprint" |
| Zugriff Claude | Atlassian-Connector | GitHub-Connector oder `gh` CLI | Dateien direkt |

Fehlt Claude der Zugriff aufs Tool in einer Session, werden die Aktionen (Kommentar-Text, Zeit, Status) im Chat ausgegeben, damit der User sie manuell übernehmen kann.

## Projekt-Konfiguration (beim Kickoff ausfüllen)

| Feld | Wert |
|---|---|
| Tool | GitHub Issues / Projects (entschieden 21.10.2026; kein Jira, weil RDG Open Source wird und der KI-Maintainer auf GitHub Issues reagiert) |
| Projekt-URL | <URL> |
| Issue-Prefix | <PREFIX> |
| Status-Mapping / Transition-IDs | To Do: <id>, In Progress: <id>, In Review: <id>, Done: <id> |
| Feld für AC | <Beschreibung / Custom Field> |
| Mentor-Zugriff | <ja/nein, wie> |
