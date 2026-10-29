# IDs und Dateinamen

| Objekt | Schema | Beispiel | Vergabe |
|---|---|---|---|
| Issue-Key | `<PREFIX>-<n>` | `ABC-17` | Tracking-Tool (Prefix im Steckbrief) |
| Story-Code | `<EPIC>-<n>` | `INF-3` | Backlog, Epic-Kürzel 2 bis 4 Buchstaben |
| Finding | `F-NNN` | `F-042` | Global fortlaufend, `docs/13_deferred_findings.md` |
| Demo | `D-NNN` | `D-007` | Global fortlaufend über alle Sprints |
| Risiko | `R-<Kat><NN>` | `R-T04` | Kategorien: T Technisch, S Termin, K Wissen, E Extern, P Persönlich |
| ADR | `ADR-NNN` | `ADR-003` | `docs/adr/` |
| Use Case | `UC-<n>` | `UC-2` | `docs/05_requirements.md` |
| Functional Req. | `FR-<Bereich>-<n>` | `FR-Auth-1` | `docs/05_requirements.md` |
| Non-Functional Req. | `NFR-<Bereich>-<n>` | `NFR-Sec-2` | `docs/05_requirements.md` |

## Dateinamen

| Artefakt | Pfad |
|---|---|
| Evidence | `sprint_journal/sprint_<n>/evidence/<KEY>_<CODE>_<kurz>.md` |
| Demo | `sprint_journal/sprint_<n>/demos/D-NNN_<thema>.md` |
| Demo-Screenshot | `sprint_journal/sprint_<n>/demos/D-NNN_screenshot_<seq>.png` |
| Evidence-Bilder | `sprint_journal/sprint_<n>/evidence/images/<KEY>_<seq>.png` |
| Mentor-Termin | `sprint_journal/mentor_meetings/<YYYY-MM-DD>_<thema>.md` |
| ADR | `docs/adr/ADR-NNN-<kebab-titel>.md` |

Dateinamen: Kleinbuchstaben, Unterstriche, keine Umlaute und Leerzeichen.
