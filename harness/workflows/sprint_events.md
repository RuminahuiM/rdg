# Sprint-Events und Mentor-Termine (Strategie-Chat)

Solo-Scrum-Adaption, Details in `docs/08_scrum_setup.md`. Templates in `sprint_journal/_templates/`.

| Event | Wann | Datei | Template |
|---|---|---|---|
| Sprint Planning | Erster Arbeitstag des Sprints | `sprint_<n>/01_planning.md` | `sprint_planning_template.md` |
| Daily Journal | Pro Arbeitstag, auf Anweisung des Users | `sprint_<n>/02_daily_journal.md` | `daily_journal_template.md` |
| Sprint Review | Letzter Arbeitstag | `sprint_<n>/03_review.md` | `sprint_review_template.md` |
| Retrospektive | Nach dem Review | `sprint_<n>/04_retrospective.md` | `sprint_retrospective_template.md` |
| Mentor-Termin | Feste Termine laut Steckbrief | `mentor_meetings/<datum>_<thema>.md` | `mentor_meeting_template.md` |

## Pflichtpunkte

- **Planning:** Nur reale Arbeitstage und Kapazität laut Steckbrief, ca. 20 Prozent Reserve. DoR-Check pro Story. Offene Findings mit Sprint-Trigger und Active-Risiken einbeziehen.
- **ADRs:** Im Planning offene Proposed-ADRs mit Sprint-Bezug entscheiden oder Entscheid terminieren. Im Review neue und geänderte ADRs auflisten. Vor Mentor-Terminen wichtige oder offene ADRs als Diskussionspunkt aufnehmen.
- **Daily Journal:** Pro Arbeitstag max. drei Sätze plus Zeit-Tracking-Tabelle. Evidence-Links für Done-Stories.
- **Review:** AC und DoD pro Story prüfen, Velocity, Zeit-Tracking aggregieren (AI-Multiplier nach Story-Typ), Risk Review gegen Register, Findings-Stand.
- **Retro:** Drei Achsen (Produkt, Prozess, Selbstmanagement), Top 3 Massnahmen, Erkenntnisse für das Reflexions-Kapitel.
- **Mentor-Termin:** Vorbereitung 2 bis 3 Tage vorher inkl. Demo; Feedback und Action Items festhalten; Action Items ins Backlog.

Sprint Review und Mentor-Termin sind getrennte Events: Review ist Selbst-Inspektion, Mentor-Termin ist externes Stakeholder-Review.
