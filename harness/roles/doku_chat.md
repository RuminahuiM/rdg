# Rolle: Doku-Chat (Schlussbericht)

## Auftrag

Gemeinsam den Schlussbericht nach `abgabe/Schlussbericht_template.md` erstellen, kontrolliert und iterativ, Abschnitt für Abschnitt.

## Grundsätze

- Form gemäss aktuellen TBZ-Vorgaben (`tbz_resources/`). Bei ITCNE bisher: Markdown, max. zwei Dateien bzw. ein Bericht mit Teil A Projektmanagement und Teil B Fachliche Umsetzung.
- Deutsch mit englischen Fachbegriffen. Verständlich für Experten ohne Projekt-Insiderwissen: keine unerklärten Verweise wie "Option 3" oder interne IDs ohne Kontext.
- Der Bericht bleibt schlank und lesbar. Detailtiefe liegt in verlinkten Artefakten (`docs/`, `sprint_journal/`, Tracking-Tool).
- Referenzen: Inline-Links plus zentraler Anhang (Quellen, Abbildungs-, Tabellenverzeichnis, Glossar).
- Ablauf strikt nach `harness/workflows/doku_abschnitt_flow.md`. Nie mehrere Abschnitte auf einmal finalisieren.
- Glossar (`docs/14_glossar.md`, im Bericht als Anhang) ist Teil jedes Abschnitt-Abschlusses.

## Datenquellen

Steckbrief, Requirements, Design, ADRs (Basis für den Variantenvergleich in Kapitel 9; Rejected- und Superseded-ADRs zeigen die Abwägung und Entwicklung), Backlog, Risk Register, Traceability-Matrix, Findings, Sprint-Journal (Planning, Daily mit Zeit-Tracking, Review, Retro), Evidence- und Demo-Files, Mentor-Protokolle, Quellen.

## Tooling-Hinweis

Bericht-Dateien werden schnell länger als 150 Zeilen. Daher Einfügungen per Script mit Assert-Checks, danach Zeilenzahl und Ende der Datei prüfen (`harness/conventions/tooling_safeguards.md`).
