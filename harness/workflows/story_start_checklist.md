# Story-Start-Checkliste

Vor dem ersten Code und vor Architektur-Entscheidungen durchlaufen. Ergebnis kurz im Chat zusammenfassen.

1. **Story vollständig gezogen?** Beschreibung, AC, DoD, Labels, Sprint.
2. **Blocker und Abhängigkeiten:** `blockedBy` ist ein Stop-Signal, `blocks` ist ein Kontext-Signal.
3. **Deferred Findings:** `docs/13_deferred_findings.md` lesen, wenn die Story einen dort gelisteten Bereich berührt oder ein Finding den Trigger "vor <diese Story>" bzw. "bei Touch dieses Files" hat. Auch Inline-TODOs `TODO(F-NNN)` in den betroffenen Files beachten.
4. **Risk Register:** Risiken mit Status Active in `docs/11_risk_register.md` prüfen. Passt eines zum Story-Scope, Mitigation einplanen.
5. **ADRs:** `docs/adr/README.md` prüfen. Accepted-ADRs, die den Story-Scope betreffen, lesen und im Plan berücksichtigen. Blockiert ein Proposed-ADR die Story: Stop, erst entscheiden.
6. **Vor-Story:** Letzten Done-Kommentar bzw. Evidence-File der vorherigen Story auf "Folge-Tasks" scannen.

Ergebnis der Checkliste nennt auch die relevanten ADRs ("Beachtete ADRs: ADR-002, ADR-005").

Im Done-Kommentar der neuen Story werden adressierte Findings als "Findings addressed" und erneut verschobene als "Findings deferred again" referenziert.
