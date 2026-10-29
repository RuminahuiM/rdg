# Risk Register

## 1. Methodik

- **Kategorien:** Technisch (T), Termin (S), Wissen (K), Extern (E), Persönlich (P)
- **Bewertung:** Probability und Impact je Niedrig / Mittel / Hoch
- **Reaktion:** pro Risiko Mitigation (vorbeugend) und Contingency (bei Eintritt)
- **Review:** in jedem Sprint Review (Risk Review) und in Mentor-Terminen

| Probability \ Impact | Niedrig | Mittel | Hoch |
|---|---|---|---|
| **Niedrig** | 1 | 2 | 3 |
| **Mittel** | 2 | 4 | 6 |
| **Hoch** | 3 | 6 | 9 |

Score ab 4: Active Watch. Score ab 6: High Priority.

Status-Werte: Active, Monitor, Mitigated (Datum), Eingetreten, Accepted, Closed.

## 2. Risiko-Matrix

| ID | Titel | Kat. | Prob. | Impact | Score | Status |
|---|---|---|---|---|---|---|
| R-S01 | Sprint-Kapazität wird systematisch überschritten | Termin | Hoch | Mittel | 6 | Active |
| R-S02 | Doku-Zeit am Ende zu kurz | Termin | Hoch | Hoch | 9 | Active |
| R-S03 | Externe Abhängigkeiten (Accounts, Zugänge, Freigaben) verzögern Sprints | Termin | Mittel | Mittel | 4 | Active |
| R-K01 | Fachliche Verständnistiefe nicht ausreichend | Wissen | Mittel | Mittel | 4 | Active |
| R-K02 | ScrumBut-Falle in Solo-Anwendung | Wissen | Mittel | Mittel | 4 | Active |
| R-P01 | Motivationsverlust oder Überlastung | Persönlich | Mittel | Hoch | 6 | Active |
| R-P02 | Berufliche und private Belastungen | Persönlich | Mittel | Mittel | 4 | Active |
| R-P03 | Krankheit oder unerwartete Ausfälle | Persönlich | Niedrig | Hoch | 3 | Monitor |
| R-T01 | <projektspezifisches technisches Risiko> | Technisch | | | | |

## 3. Details

### R-S01: Sprint-Kapazität wird systematisch überschritten
- **Beschreibung:** Stories dauern länger als geschätzt, Carry-Over häuft sich.
- **Mitigation:** 20 Prozent Reserve, Zeit-Tracking pro Story, Scope-Check in jedem Review.
- **Contingency:** Should/Could-Stories streichen, Product Goal schärfen.

### R-S02: Doku-Zeit am Ende zu kurz
- **Mitigation:** Feature-Freeze laut Steckbrief, Evidence-Files und Retro-Erkenntnisse laufend, Bericht-Abschnitte früh anlegen.
- **Contingency:** Polish-Findings streichen, Fokus auf Bewertungskriterien.

### R-S03: Externe Abhängigkeiten verzögern Sprints
- **Mitigation:** Zugänge in Sprint 0 beantragen, Mock-Varianten bereithalten.
- **Contingency:** Story umplanen, Mock verwenden und als Limitation dokumentieren.

### R-K01: Fachliche Verständnistiefe nicht ausreichend
- **Mitigation:** Technical Brief, WebSearch pro Story, Mentor-Fragen.
- **Contingency:** Scope verkleinern, Theorie-Teil vertiefen.

### R-K02: ScrumBut-Falle
- **Mitigation:** Templates, feste Events, Retro-Achse Prozess.
- **Contingency:** Abweichungen bewusst dokumentieren und begründen.

### R-P01, R-P02, R-P03: Persönliche Risiken
- **Mitigation:** realistischer Arbeitsrhythmus, Pausen einplanen, Puffer vor Abgabe.
- **Contingency:** Scope-Reduktion, frühzeitige Kommunikation mit Experten.

## 4. Historie

| Datum | Änderung |
|---|---|
