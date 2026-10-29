# Kickoff: neue Semesterarbeit aufsetzen

Wird im ersten Chat des neuen Projekts abgearbeitet (Rolle: Strategie-Chat). Ergebnis ist ein vollständig ausgefüllter `docs/00_projekt_steckbrief.md`, ein gewähltes Tracking-Tool, ein befülltes Tech-Profil und ein initialer Plan bis zur Einreichung.

Jeden Block mit dem User klären (AskUserQuestion), nicht annehmen. Ergebnisse sofort in die genannten Dateien schreiben.

## Block A: Rahmen

- [ ] Titel (Arbeitstitel reicht vorerst), Semester, Studiengang/Klasse
- [ ] Form: Solo oder Gruppe; gewählte Module/Themenfelder (z.B. Projektmanagement Pflicht plus Fachmodul)
- [ ] Termine: Einreichung Formular, Mentor-Termine (meist drei), Abgabe Bericht, Kolloquium
- [ ] Arbeitsrhythmus: an welchen Tagen und mit wie vielen Stunden wird gearbeitet (z.B. Wochenenden 6 bis 8 h, Mittwochabend 2 bis 3 h)
- [ ] Harte Regeln zur Zeitplanung, z.B. "Feature-Freeze X Wochen vor Abgabe, danach nur Doku"
- [ ] TBZ-Vorgaben aktuell? `tbz_resources/` gegen die aktuellen Merkblätter des Semesters prüfen und ggf. ersetzen

Ziel-Datei: `docs/00_projekt_steckbrief.md`

## Block B: Thema und Ziele

- [ ] Problemstellung und Motivation in 3 bis 5 Sätzen
- [ ] Mindestens drei messbare (SMART) Ziele
- [ ] Scope und bewusste Abgrenzung
- [ ] Erste Recherche (WebSearch) zu Stand der Technik 2026+, Ergebnisse in `docs/02_technical_brief.md` und Quellen in `docs/04_quellen.md`
- [ ] Grundsatzentscheidungen (Architektur-Muster, Stack, Hosting, Scope) als erste ADRs nach `harness/workflows/adr_workflow.md` anlegen und entscheiden. Das zahlt auf das Bewertungskriterium "Lösungen abwägen" (B1.2) ein

Ziel-Dateien: `docs/01_einreichungsformular.md`, `docs/02_technical_brief.md`, `docs/adr/`

## Block C: Tracking-Tool

- [ ] Tool wählen: Jira, GitHub Issues/Projects oder reines Markdown-Backlog
- [ ] Issue-Key-Prefix festlegen (z.B. `ABC`), Story-Code-Schema (Epic-Kürzel plus Nummer, z.B. `INF-1`)
- [ ] Status-Workflow To Do, In Progress, In Review, Done im Tool abbilden
- [ ] Mentor-Zugriff klären
- [ ] Mapping in `docs/10_tracking_setup.md` und `harness/conventions/tracking_adapter.md` (Abschnitt "Projekt-Konfiguration") eintragen

## Block D: Tech-Profil

- [ ] Stack grob festlegen (Sprachen, Frameworks, Runtime, Infra)
- [ ] Verifikations-Befehle (Tests, Lint, Format, Typecheck, Build, Syntax-Check)
- [ ] Stack-spezifische Review-Punkte je Kategorie
- [ ] WebSearch-Stichworte für Best-Practice-Checks

Ziel-Datei: `harness/tech_profile.md`, Details später in `docs/06_tech_stack.md`

## Block E: Repo und Ablage

- [ ] Git-Repo anlegen (z.B. GitHub), Name und Bedeutung festhalten
- [ ] Hinweis: Git-Repos in OneDrive-synchronisierten Ordnern können Lock-Probleme verursachen. Entweder Repo ausserhalb von OneDrive führen oder OneDrive-Sync für `.git` ausschliessen
- [ ] `.gitignore` prüfen und für den Stack ergänzen
- [ ] Mentoren als Collaborators einladen (falls gewünscht)

## Block F: Planung bis Einreichung

- [ ] Sprint-Länge und Sprint-Kalender (nur reale Arbeitstage zählen)
- [ ] Sprint 0 definieren: Tooling, Repo, Skelett, Requirements, Design-Grundlagen
- [ ] Erste Risiken ins Risk Register (`docs/11_risk_register.md`), Standard-Risiken übernehmen und projektspezifische ergänzen
- [ ] Einreichungsformular-Entwurf finalisieren

## Abschluss

- [ ] Steckbrief vollständig (keine `<Platzhalter>` mehr)
- [ ] User bestätigt den Kickoff explizit
- [ ] Erste Sprint-Planning-Datei aus Template anlegen (`sprint_journal/sprint_0/01_planning.md`)
