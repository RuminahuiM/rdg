# Done-Flow (nach explizitem User-OK)

Reihenfolge:

1. **Worklog** im Tracking-Tool: tatsächliche Zeit (`timeSpent`, Startzeit, kurzer Kontext). Ohne Tool-Support: in der Evidence-Datei und der Session-Summary festhalten.
2. **Status Done** setzen.
3. **Done-Kommentar** im Tracking-Tool:

```
**Done Note (TT.MM.JJJJ)**

Erledigt:
- <Punkt>

Abweichungen von den ACs:
- <AC, was anders, warum>

ADRs:
- Angewendet: ADR-NNN
- Neu erstellt / geändert: ADR-NNN (Status)

Findings:
- Im Review gefixt: F-NNN, ...
- Deferred: F-NNN (Tier 1/2/4, Trigger)
- Addressed aus früheren Stories: F-NNN

Links:
- Evidence: sprint_journal/sprint_<n>/evidence/<KEY>_<CODE>_<kurz>.md
- Commit: <hash>
```

Abschnitte ohne Inhalt weglassen, "Erledigt" ist Pflicht.

4. **Evidence-File** aus `sprint_journal/_templates/evidence_template.md` unter `sprint_journal/sprint_<n>/evidence/` anlegen bzw. finalisieren. Ohne Evidence kein Done (Teil der DoD).
5. **Git-Commit** gemäss `../conventions/git.md` (lokal, kein Push).
6. **Demo-Check** (Phase 8 Closing-Review), falls nicht schon erfolgt.

## Zeit-Tracking und AI-Multiplier

- Backlog-Schätzungen sind bewusst klassische Solo-Schätzungen ohne AI. Mapping T-Shirt zu Stunden steht in `docs/08_scrum_setup.md`.
- Pro Story wird die tatsächliche Zeit erfasst. Die Tabelle "Zeit-Tracking pro Story" im Daily Journal füllt der User am Ende der Session in einem Rutsch (nicht pro Story automatisch).
- Multiplier = geschätzte Stunden / tatsächliche Stunden. Auswertung im Sprint Review (nach Story-Typ) und im Schlussbericht.
