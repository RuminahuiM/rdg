# Tech-Profil RDG (vorbefüllt am 21.10.2026 aus RDG_Base, im Kickoff bestätigen)

Ergänzt die generischen Regeln um Stack-spezifische Punkte. Wird von Lifecycle (Schritt 3 und 7) und Closing-Review (Phase 1 und 2) referenziert. Quelle der Werte: `RDG_Base/.github/workflows/ci.yml` und RDG-Design-Docs (`docs/design/`). Bei Widerspruch gilt der Code im Repo.

## 1. Stack

| Bereich | Wahl | Version | Begründung / ADR |
|---|---|---|---|
| Sprache(n) | PowerShell (Engine, Runbooks, API, Tools), TypeScript (Web-App), HCL (OpenTofu) | PowerShell 7.4, Node 22 | RDG-Design `01-solution-design.md` |
| Framework(s) | Eigenes Modul `DgEngine`; Azure Functions (PowerShell); React mit Fluent UI, Vite | siehe `src/Web/package.json` | RDG-Design `12`, `13` |
| Runtime / Hosting | Azure Automation (Runbooks), Azure Function App (Consumption, Run-from-Package), Azure Static Web App (Standard) | | RDG-Design `16` |
| Orchestrierung | Kein Kubernetes (Ausnahme der Lehrer, 21.10.2026) | | ADR folgt |
| IaC | OpenTofu, Module app, core, data, engine, monitoring; TFLint (azurerm) | OpenTofu 1.12.6, TFLint 0.64.0 | RDG-Design `16` |
| CI/CD | GitHub Actions (`ci.yml`, `release.yml`), Release-Bundle `rdg-<version>.zip`; Deploy über `deploy/Deploy-Rdg.ps1` (heute manuell, Ziel Z2: Pipeline) | | RDG-Design `17` |
| KI-Maintainer | Claude Code in GitHub Actions (Kandidat), Modell Opus | | ADR folgt (Agent-Plattform) |
| Datenhaltung | Cosmos DB for NoSQL, serverless, nur Entra-Auth | | RDG-Design `14` |
| Test-Framework | Pester 5.7.1 (Coverage 80 % auf DgEngine/DgApi), Regel-Conformance-Suite, Vitest, Playwright (E2E gegen Mock-Build), `tofu test` mit gemocktem Provider | | RDG-Design `17` |
| Security-Scans | Trivy 0.75.0 (Config-Scan `infra/`), `npm audit` (Runtime-Dependencies, ab high) | | RDG-Design `17` |
| Test-Umgebung | Eigener Test-Tenant mit Azure Pay-as-you-go ("Kunden-Tenant") | | ADR folgt |

## 2. Verifikations-Befehle

Lokal im Repo-Root (Windows, PowerShell 7), dieselben Befehle wie in CI.

| Zweck | Befehl | Wo ausführen |
|---|---|---|
| PowerShell-Lint | `./tools/Invoke-Lint.ps1` | Repo-Root |
| Pester (volle Suite) | `Invoke-Pester` mit Konfiguration wie im CI-Job `engine` (Pfade `./tests/*`, Coverage 80 %) | Repo-Root |
| Regel-Conformance | `./tools/Invoke-RuleConformance.ps1` | Repo-Root |
| Contracts (Schemas, OpenAPI) | `npm ci; npm run contracts:check` | Repo-Root |
| Web: Format, Lint, Types | `npm run format:check; npm run lint; npm run typecheck` | `src/Web` |
| Web: Unit-Tests | `npm test` | `src/Web` |
| Web: Build und E2E | `npm run build; npm run build:mock; npm run test:e2e` | `src/Web` |
| IaC | `tofu fmt -recursive -check; tofu init -backend=false; tofu validate; tflint --recursive; tofu test -var-file=../examples/contoso.tfvars` | `infra` |
| Security | `trivy config --severity MEDIUM,HIGH,CRITICAL --tf-vars examples/contoso.tfvars infra`; `npm audit --omit=dev --audit-level=high` | Repo-Root / `src/Web` |
| Syntax-/Truncation-Check PowerShell | `pwsh -NoProfile -c "$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('<file>',[ref]$null,[ref]$e); if($e){$e; exit 1}"` | beliebig |
| Build Release-Bundle | `./tools/Build-Release.ps1 -Version 0.0.0-local -OutputPath ./out/release` | Repo-Root |
| Smoke-Test | Deploy-Schritt `SmokeTest` in `deploy/Deploy-Rdg.ps1` gegen die Testumgebung | Pipeline / Testumgebung |

Hinweis: Nicht im OneDrive-Ordner bauen und keine `npm install` dort (siehe Briefing). Gebaut wird im Repo-Clone ausserhalb OneDrive.

## 3. Stack-spezifische Review-Punkte (Ergänzung zu den 10 Kategorien)

| Kat. | Prüfpunkte für diesen Stack |
|---|---|
| 1 Code-Standards | PSScriptAnalyzer-Regeln aus `PSScriptAnalyzerSettings.psd1`, ESLint, Prettier, `tsc --noEmit`, `tofu fmt` |
| 2 Framework | Aktuelle Microsoft Graph / Exchange Online PowerShell Cmdlets, keine deprecated Graph-Endpoints; React/Fluent UI aktuelle Patterns; GitHub Actions ohne deprecated Syntax |
| 3 Build/Setup | Lockfiles (`package-lock.json`, `.terraform.lock.hcl`), gepinnte Modul-Versionen mit `# renovate:`-Kommentar, Bundle reproduzierbar ("built once, deployed many times") |
| 4 Runtime/Deployment | Managed Identities mit Least Privilege, `access_mode` read-only/read-write durch Rechte erzwungen, Sicherheitsbremsen (leeres Resultat, Change-Limit, Dry run) nicht umgangen |
| 5 Config/Secrets | Keine gespeicherten Secrets (Workload Identity Federation, Managed Identities, Key Vault), keine echten `tfvars` im Repo, GitHub Secrets nur wo unvermeidbar |
| 6 Logging/Observability | Run-Records in Cosmos DB, Metric Alerts, keine Benutzerdaten (PII) in Logs oder Agent-Prompts |
| 7 Schnittstellen/Netzwerk | API nur mit Entra-Login (Rollen Admin/Reader), Validierung über JSON-Schemas/OpenAPI, kein Drift zwischen OpenAPI und Web-Typen |
| 8 Betrieb/Resilienz | Smoke-Test nach Deploy, Rollback über vorherige Bundle-Version, Locking der Runbooks, Notstopp "Pause all syncing" |
| 9 Supply Chain | Actions auf Commit-SHA gepinnt, Trivy, `npm audit`, Renovate, Build-Provenance (`actions/attest`), Checksummen der Bundles |
| 10 Tests/Doku | Pester-Coverage 80 %, Conformance-Fall pro Regeländerung, englische Produkt-Doku aktuell, keine Semester-Doku im Repo |
| Zusatz KI-Maintainer | Agent kann nicht auf `main` pushen, minimale Token-Rechte (`permissions:`), reagiert nur auf berechtigte Issues/Labels, kein Zugriff auf produktive Tenants, Kostenlimit pro Lauf, Prompt-Injection-Test |

## 4. WebSearch-Stichworte

- "GitHub Actions security hardening 2026"
- "claude code github action issue to pull request 2026"
- "prompt injection github issues ai agent 2026"
- "OpenTofu azurerm best practices 2026"
- "Pester 5 best practices 2026"
- "Microsoft Graph PowerShell group membership best practices 2026"
- "DORA metrics GitHub Actions 2026"

## 5. Bekannte Eigenheiten und Lessons

- 21.10.2026: OneDrive hält Dateien teils nur online; Shell-Zugriff schlägt dann mit "Invalid argument" fehl (siehe `conventions/tooling_safeguards.md`).
- Aus dem RDG-Testbetrieb (Briefing): Fehlertext-Erkennung im Bootstrap und im Exchange-Writer ist sprachabhängig (englische Texte), fragil.
