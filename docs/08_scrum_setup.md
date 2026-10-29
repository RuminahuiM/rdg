# Scrum-Setup (Solo-Adaption)

> Generischer Rahmen aus bisherigen Semesterarbeiten. Beim Kickoff auf das Projekt anpassen (Sprint-Länge, Kapazität, Termine).

## 1. Zweck und Quellen

Beschreibt, wie Scrum in einer Solo-Arbeit gelebt wird. Grundlage: Scrum Guide 2020, `tbz_resources/Komplette-Scrum-Theorie-in-einem-Dokument.md`.

## 2. Rollen in der Solo-Arbeit

| Verantwortlichkeit | Wer | Wie gelebt |
|---|---|---|
| Product Owner | Studierende/r | Backlog-Priorisierung, Abnahme im Review |
| Scrum Master | Studierende/r, unterstützt durch Claude (Strategie-Chat) | Prozesspflege, Retro, Impediments |
| Developers | Studierende/r, unterstützt durch Claude (Implementation-Chat) | Umsetzung, Closing-Review |

### 2.1 Bekannte Limitationen und Gegenmassnahmen

| Limitation | Gegenmassnahme |
|---|---|
| Keine Rollentrennung, Gefahr ScrumBut | Feste Events mit Templates, Retro-Achse "Prozess" |
| Kein Team-Daily | Daily Journal pro Arbeitstag |
| Kein externes Review pro Sprint | Mentor-Termine als Stakeholder-Review, Closing-Review pro Story |

## 3. Events

| Event | Timebox | Umsetzung |
|---|---|---|
| Sprint | <2 Wochen> | Nur reale Arbeitstage zählen |
| Planning | 2 h | `sprint_journal/sprint_<n>/01_planning.md` |
| Daily | 5 min | Daily Journal |
| Review | 1 h | `03_review.md` |
| Retro | 45 min | `04_retrospective.md` |

## 4. Artefakte und Commitments

- **Product Backlog** mit Product Goal: `09_product_backlog.md` plus Tracking-Tool
- **Sprint Backlog** mit Sprint Goal: Planning-Datei
- **Increment** mit Definition of Done

### 4.1 Product Goal

<Ein Satz>

### 4.2 Definition of Ready

- User-Story-Format oder klare technische Beschreibung
- Mindestens zwei Akzeptanzkriterien
- Abhängigkeiten geklärt
- Geschätzt (T-Shirt und Story Points)
- Bezug zu Requirement vorhanden
- Klein genug für einen Sprint

### 4.3 Definition of Done

- Akzeptanzkriterien nachprüfbar erfüllt
- Verifikation gemäss `harness/tech_profile.md` grün (volle Test-Suite, Lint, Typecheck)
- Für funktionale Änderungen mindestens ein automatisierter Test (Happy Path plus relevanter Fehlerfall) oder dokumentierter manueller Test mit Screenshot
- Closing-Review durchgeführt, Findings getrackt (`13_deferred_findings.md`)
- Keine offenen kritischen TODOs ohne Finding-ID
- Relevante Doku aktualisiert (README, Design, Tech-Stack)
- Relevante Accepted-ADRs eingehalten; ADR-würdige Entscheidungen der Story als ADR dokumentiert und entschieden
- Quellen für nicht-trivialen Code in `04_quellen.md`
- Evidence-File angelegt
- Status Done mit Done-Kommentar, Worklog erfasst
- Lokaler Git-Commit

## 5. Schätzung

| T-Shirt | Story Points | Stunden (Mittel, ohne AI) |
|---|---|---|
| XS | 1 | 1 h |
| S | 2 bis 3 | 3 h |
| M | 5 | 7 h |
| L | 8 | 15 h |
| XL | 13 | zerlegen |

### 5.1 AI-Multiplier

Schätzungen sind bewusst klassische Solo-Schätzungen ohne AI. Tatsächliche Zeit wird pro Story erfasst. Multiplier = Schätzung / tatsächlich, ausgewertet pro Sprint und im Schlussbericht (nach Story-Typ).

## 6. Kapazität und Reserve

Kapazität laut Arbeitsrhythmus im Steckbrief, Reserve ca. 20 Prozent pro Sprint.

## 7. Qualitätssicherung

Closing-Review pro Story (`harness/workflows/closing_review.md`), Demos (`harness/workflows/demo_convention.md`), Mentor-Termine.
