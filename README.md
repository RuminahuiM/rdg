# SemHarness: Arbeits-Harness für Semesterarbeiten (TBZ HF)

> Instanz für die Semesterarbeit 4 (RDG, ITCNE25). Liegt nur lokal in `00_RDG/`. Einstieg für Claude: `CLAUDE.md`.

Dieser Ordner ist ein wiederverwendbares Arbeitsgerüst, um eine Semesterarbeit mit Claude als Co-Scrum-Master, Senior Engineer und Doku-Partner zu planen, umzusetzen und zu dokumentieren. Er destilliert die Prozesse, Konventionen und Templates, die sich in der Semesterarbeit "Implementing PQC" (Semester 3, 2026) bewährt haben, in eine projekt- und tool-neutrale Form.

## Was drin ist

| Ordner / Datei | Zweck |
|---|---|
| `CLAUDE.md` | Einstiegspunkt für Claude: Pflichtregeln, Rollen, wo was liegt. Wird zu Beginn jeder Session gelesen. |
| `PROJECT_INSTRUCTIONS.md` | Text zum Einfügen in die Instruktionen des neuen Claude-Projekts. |
| `harness/` | Das eigentliche Regelwerk: Rollen, Workflows, Konventionen, Tech-Profil, Kickoff. |
| `docs/` | Projekt-Dokumente als Templates (Steckbrief, Requirements, Design, Backlog, Risk Register, Findings, Glossar, ADRs). |
| `sprint_journal/` | Sprint-Templates (Planning, Daily, Review, Retro, Mentor, Evidence, Demo) und Ablage pro Sprint. |
| `abgabe/` | Template für den Schlussbericht. |
| `praesentation/` | Checkliste und Runbook-Template fürs Kolloquium. |
| `tbz_resources/` | TBZ-Merkblätter und Vorgaben (Stand 2026, bei neuem Semester auf Aktualität prüfen). |
| `scripts/` | Platz für Demo- und Verifikations-Scripts des Projekts. |

## So startest du eine neue Semesterarbeit

1. Optional: eine saubere Kopie dieses Ordners behalten (z.B. als ZIP), damit der Harness für spätere Arbeiten unverändert bleibt.
2. Neues Claude-Projekt anlegen, diesen Ordner verbinden.
3. Den Inhalt von `PROJECT_INSTRUCTIONS.md` in die Projekt-Instruktionen kopieren.
4. Im ersten Chat sagen: "Kickoff starten". Claude arbeitet dann `harness/00_kickoff.md` ab (Steckbrief, Tracking-Tool, Tech-Profil, Termine, Repo).
5. Danach drei Chats nach Rolle führen (siehe `harness/roles/`):
   - Strategie-Chat (Co-SM / Co-Projektleitung)
   - Implementation-Chat (Senior Engineer)
   - Doku-Chat (Schlussbericht, Abschnitt für Abschnitt)

## Grundprinzip

Alle Regeln liegen als Files im Projekt, nicht im Chat-Memory. Damit gelten sie in jeder Session und in jedem Chat gleich, und Anpassungen sind versioniert. Wenn sich während der Arbeit eine neue Regel etabliert, wird sie in der passenden Harness-Datei ergänzt (mit Datum und kurzer Begründung), nicht nur im Chat vereinbart.
