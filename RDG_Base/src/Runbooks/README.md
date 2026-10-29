# Runbooks

Entry scripts for Azure Automation (PowerShell 7.4):

- `Sync-Groups.template.ps1` becomes `Sync-EntraGroups.ps1` and `Sync-ExchangeGroups.ps1`.
- `Renew-SignInCertificate.ps1` keeps the sign-in app's certificates in step with Key Vault.

`tools/Build-Runbook.ps1` writes the deployable files to `out/runbooks/`, each a single file with DgEngine inlined at the `#{{DgEngine}}` line. Settings come from Automation variables (see the Runbooks design). `tests/Runbooks/` runs the built files in a fake Automation sandbox.
