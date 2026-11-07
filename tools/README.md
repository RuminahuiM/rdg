# Tools

Developer scripts. `Invoke-Lint.ps1` runs the same PSScriptAnalyzer check as CI.

| Script                       | What it does                                                                 |
| ---------------------------- | ---------------------------------------------------------------------------- |
| `Invoke-Lint.ps1`            | PSScriptAnalyzer with the repo rules (CI job "powershell lint")               |
| `Invoke-RuleConformance.ps1` | the rule conformance suite in `tests/rules`                                  |
| `Build-Runbook.ps1`          | the three runbooks, each one file with DgEngine inlined                      |
| `Build-ApiPackage.ps1`       | the Function App package (`-Local` for `func start`)                         |
| `Build-Release.ps1`          | `rdg-<version>.zip` and `SHA256SUMS`, with the version stamped (release.yml) |
| `Export-RuleProperties.ps1`  | the property list of the web app's rule editor                               |
| `Start-ApiLocal.ps1`         | runs the API locally                                                         |
