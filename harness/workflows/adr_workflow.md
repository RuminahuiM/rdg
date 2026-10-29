# ADR-Workflow (Architecture Decision Records)

ADRs halten Architektur- und Technologie-Entscheidungen fest, während sie getroffen werden, nicht rückwirkend am Projektende. Sie sind die Belegbasis für "Lösungen werden abgewogen, Varianten gegenübergestellt" (Kompetenzmatrix B1.2) und fliessen direkt in Kapitel 9 des Schlussberichts.

Ablage: `docs/adr/ADR-NNN-<kebab-titel>.md`, Index in `docs/adr/README.md`, Vorlage `docs/adr/ADR-000-template.md` (MADR-light).

## 1. Wann entsteht ein ADR (Trigger)

Claude prüft in jeder Rolle aktiv, ob einer dieser Trigger vorliegt, und schlägt dann ein ADR vor:

| Nr. | Trigger | Beispiele |
|---|---|---|
| 1 | Wahl zwischen mindestens zwei ernsthaften Alternativen mit Auswirkung über eine Story hinaus | Framework, Datenbank, Orchestrierung, Auth-Verfahren |
| 2 | Entscheidung, die teuer rückgängig zu machen ist | Datenmodell, Schnittstellen-Format, Deployment-Modell |
| 3 | Bewusste Abweichung von Best Practice, Standard oder Vorgabe | "Kein HA-Setup, weil Demo-Scope" |
| 4 | Fixierung einer Version, Plattform oder externen Abhängigkeit für das ganze Projekt | SDK-Version, Cloud-Provider, Tenant-Modell |
| 5 | Security- oder Compliance-relevante Grundsatzentscheidung | Secret-Handling, Verschlüsselung, Zugriffskonzept |
| 6 | Scope-Entscheidung mit Architekturfolgen | "Broker statt eigener Identity Provider" |
| 7 | Ein bestehendes ADR soll geändert werden | Neues ADR, das das alte ersetzt |

Kein ADR für: reine Implementierungsdetails innerhalb einer Story, Code-Style, Entscheidungen ohne echte Alternative. Im Zweifel kurz fragen.

## 2. Lebenszyklus

```
Proposed  -> Accepted -> (Superseded by ADR-NNN | Deprecated)
          -> Rejected
```

| Status | Bedeutung |
|---|---|
| Proposed | Entwurf von Claude oder User, Optionen und Empfehlung ausgearbeitet, noch nicht entschieden |
| Accepted | User hat explizit zugestimmt. Ab jetzt verbindlich für alle Stories |
| Rejected | Vorschlag verworfen, Begründung im ADR. Bleibt als Beleg der Abwägung erhalten |
| Superseded by ADR-NNN | Durch neueres ADR ersetzt. Gegenseitige Verlinkung Pflicht |
| Deprecated | Nicht mehr relevant (z.B. Komponente entfernt), ohne Nachfolger |

Regeln:

- **Accepted nur mit explizitem User-OK**, analog zum Done-Status von Stories.
- **Accepted-ADRs werden inhaltlich nicht mehr umgeschrieben.** Erlaubt sind nur Status-Änderungen, Links und ein datierter Abschnitt "Nachträge" (z.B. Bestätigung durch spätere Erkenntnis). Eine geänderte Entscheidung ist immer ein neues ADR mit `Supersedes`.
- **Nummern** global fortlaufend, nie wiederverwenden, auch nicht bei Rejected.
- Ein Proposed-ADR, das eine Story blockiert, wird vor Story-Start entschieden oder die Story wartet.

## 3. Ablauf beim Erstellen

1. Trigger erkannt und im Chat benannt ("Das ist ADR-würdig, Trigger 1 und 2").
2. WebSearch zu den Optionen (aktuelles Jahr), Quellen in `docs/04_quellen.md`.
3. ADR als Proposed aus der Vorlage anlegen: Kontext, Entscheidungskriterien, mindestens zwei Optionen mit Vor- und Nachteilen, Empfehlung.
4. Index in `docs/adr/README.md` ergänzen.
5. User entscheidet (AskUserQuestion mit den Optionen). Bei Zustimmung Status Accepted plus Datum, bei Ablehnung Rejected plus Begründung.
6. Verlinkung nachziehen (siehe Abschnitt 4).
7. Bei Superseding: altes ADR auf `Superseded by ADR-NNN` setzen, neues mit `Supersedes ADR-NNN`.

## 4. Verlinkung (Pflicht)

| Wo | Was |
|---|---|
| `docs/adr/README.md` | Index-Zeile mit Status, Datum, Bezug |
| Betroffene Stories (Backlog / Tracking-Tool) | Feld oder Zeile "ADR: ADR-NNN" |
| `docs/07_design.md` | Abschnitt "Bezug zu ADRs" und Verweise an den betroffenen Stellen |
| `docs/06_tech_stack.md` | Spalte Begründung verweist auf das ADR |
| `docs/12_traceability_matrix.md` | Abschnitt "ADRs zu Requirements, Stories, Bewertungskriterien" |
| Evidence-File und Done-Kommentar | "ADRs umgesetzt / angewendet / neu erstellt" |
| Risk Register | Wenn ein ADR ein Risiko mitigiert oder erzeugt |

## 5. Nutzung im Projektalltag

| Zeitpunkt | Nutzung |
|---|---|
| Kickoff und Sprint 0 | Grundsatzentscheidungen (Stack, Architektur-Muster, Hosting) als erste ADRs |
| Sprint Planning | Offene Proposed-ADRs auflisten, die Stories im Sprint blockieren. Entscheidung einplanen |
| Story-Start | Für die Story relevante Accepted-ADRs lesen und einhalten (`story_start_checklist.md`) |
| Umsetzung | Abweichung von einem Accepted-ADR nur nach Rückfrage; ggf. neues ADR |
| Closing-Review | ADR-Konformität prüfen, neue ADR-Trigger aus der Story erkennen (`closing_review.md`) |
| Sprint Review | Neue und geänderte ADRs des Sprints auflisten |
| Mentor-Termin | Wichtige oder offene ADRs als Diskussionspunkt mitnehmen |
| Schlussbericht | Kapitel 9 "Architekturentscheidungen" basiert auf den ADRs, Variantenvergleiche werden daraus übernommen |

## 6. Bestätigung (Confirmation)

Jedes Accepted-ADR nennt, woran man erkennt, dass es umgesetzt ist (Test, Config-Wert, Lint-Regel, Review-Check, Demo). Das Closing-Review nutzt diese Angaben.
