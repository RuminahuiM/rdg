# Closing-Review am Story-Ende (Senior-Engineer-Review)

Trigger: Ende jeder Story (Schritt 8 im Lifecycle) oder wenn der User "Abschluss-Review", "volles Review", "Standards plus Security prüfen" sagt.

Ein Review zählt nur, wenn jede relevante Kategorie echt verifiziert wurde (Code-Lookup, Cross-Reference, File-Existenz, Config-Felder usw.). Eine Tabelle mit "OK" ohne Prüfung ist kein Review. Default ist der tiefe Pass beim ersten Mal.

## Phase 1: Vorbereitung (Pflicht, auch bei S-Stories)

1. WebSearch zu Best Practices der Story-Domain mit aktuellem Jahr (Stichworte in `../tech_profile.md`).
2. Grep über alle neuen und geänderten Files nach: `password`, `secret`, `api_key`, `token`, `TODO`, `FIXME`, `XXX`, `HACK`. Hardcoded Secrets sind sofort Must-Findings.

## Phase 2: Review entlang 10 Kategorien

Je nach Story ist ein Subset relevant; nicht relevante Kategorien mit einem Satz Begründung als "n/a" markieren. Stack-spezifische Prüfpunkte stehen in `../tech_profile.md`.

| Nr. | Kategorie | Leitfragen |
|---|---|---|
| 1 | Code-Standards und Hygiene | Lint/Format/Typecheck sauber? Idiomatisch? Keine toten Pfade? |
| 2 | Framework- und Plattform-Best-Practices | Werden aktuelle, nicht-deprecated Patterns genutzt? |
| 3 | Build, Packaging, Projekt-Setup | Reproduzierbar (Lockfiles)? Dev- und Runtime-Abhängigkeiten getrennt? |
| 4 | Runtime-, Container- und Deployment-Security | Least Privilege, Non-Root, gepinnte Images, minimale Images, sichere IaC-/K8s-Defaults? |
| 5 | Konfiguration und Secrets | Keine Secrets im Repo, saubere Trennung Config/Secret, deklarierte Settings werden auch genutzt, `.env` ignoriert? |
| 6 | Logging, Observability, Privacy | Strukturierte Logs, keine Secret-/PII-Leaks, Korrelation (Request-ID, Trace)? |
| 7 | Schnittstellen- und Netzwerk-Sicherheit | AuthN/AuthZ, Input-Validierung, CORS, Security-Header, Rate-Limits, TLS, Netzwerk-Policies? |
| 8 | Betrieb und Resilienz | Health/Readiness, Fehlerbehandlung, Timeouts, Rollback, Idempotenz? |
| 9 | Abhängigkeiten und Supply Chain | Versionen gepinnt, ungenutzte Pakete, bekannte CVEs, Herkunft? |
| 10 | Tests, Doku-Drift und ADR-Konformität | Happy Path plus Fehlerfall getestet? Stimmen README, Tech-Stack-Doku und Story-AC mit dem Stand überein? Hält der Code die relevanten Accepted-ADRs ein (Abschnitt "Bestätigung" im ADR)? Ist in der Story eine Entscheidung gefallen, die einen ADR-Trigger erfüllt, aber noch kein ADR hat? |

Pro Finding eine ID `F-NNN` (global fortlaufend, nächste freie Nummer aus `docs/13_deferred_findings.md`).

## Phase 3: Severity

| Stufe | Bedeutung |
|---|---|
| Must | Vor Done fixen: Bug, Security-Lücke, AC-Verletzung |
| Should | Vor einer abhängigen Story fixen; Trigger benennen ("vor ABC-30") |
| May | Polish, vor Bericht-Abgabe oder im letzten Sprint |
| Info | Beobachtung ohne Aktion, für Lessons Learned |

## Phase 4: Vier-Stufen-Tracking

| Tier | Ort | Wofür |
|---|---|---|
| 1 | Tracking-Tool: eigene Story mit `blockedBy` zur abhängigen Story | Konkrete Should-Fixes mit klarer Abhängigkeit |
| 2 | `docs/13_deferred_findings.md` | ALLE Findings (Pflicht), mit Severity, Trigger, Status |
| 3 | Harness-Datei | Verhaltensregel für Claude, wenn das Finding eine Prozess-Lektion ist |
| 4 | Inline im Code: `TODO(F-NNN): <Text>. Siehe docs/13_deferred_findings.md` | Wird beim nächsten Touch des Files sichtbar |

Ein Finding kann in mehreren Tiers landen (z.B. 1 plus 2 plus 4).

## Phase 5: Fix-Empfehlung an den User

1. Was in der laufenden Story noch gefixt wird (klein, ein bis zwei Items).
2. Was vor abhängigen Stories rein muss (Tier-1-Entwürfe).
3. Was als Polish in spätere Sprints geht.

Der User entscheidet. Abgelehnte Findings werden mit Begründung im Tracking notiert.

## Phase 6: Verifikation nach Fix

Code-Änderungen im Review werden erneut verifiziert (volle Suite, ggf. echter Build und Smoke-Test), bevor Done vorgeschlagen wird.

## Phase 7: Doku-Update

- Evidence-File um "Code-Review und Findings" ergänzen.
- Fehlendes ADR (nachträglich erkannter Trigger): als Proposed anlegen und im Chat zur Entscheidung vorlegen; ADR-Verstoss: Must- oder Should-Finding.
- Done-Kommentar listet "im Review gefixte Findings" und "deferred Findings mit Tracking-Ort".

## Phase 8: Demo-Check (Pflicht)

Prüfen, ob ein Demo-Trigger erreicht ist (`demo_convention.md`). Auch "kein Trigger, weil ..." explizit erwähnen.

## Ausgabe-Format an den User

Tabelle pro Severity oder Liste mit Severity-Präfix. Jede Zeile hat ID, Titel, Kategorie, Severity, Trigger und vorgeschlagene Option (A/B/C).
