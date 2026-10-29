<#
.SYNOPSIS
    Renew-SignInCertificate: keeps the RDG sign-in app's certificates in step with Key Vault.
.DESCRIPTION
    Azure Automation runbook (PowerShell 7.4), weekly, as the "maintenance" identity. Built into a
    single file with DgEngine inlined by tools/Build-Runbook.ps1. Adds Key Vault's current
    certificate to the app registration, removes expired keys, and fails on purpose when the
    app's newest key expires within 21 days (one alert for a broken renewal and a lapsing key).
#>
param()

$ErrorActionPreference = 'Stop'

#{{DgEngine}}
if (-not (Get-Command -Name Sync-DgSignInCertificate -ErrorAction SilentlyContinue)) {
    # Unbuilt script (local development): load the module from the repo.
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../DgEngine/DgEngine.psd1')
}

$config = @{
    ClientId        = Get-AutomationVariable -Name 'DG_MaintenanceClientId'
    KeyVaultUri     = Get-AutomationVariable -Name 'DG_KeyVaultUri'
    CertificateName = Get-AutomationVariable -Name 'DG_SignInCertificateName'
    SignInAppId     = Get-AutomationVariable -Name 'DG_SignInAppId'
}

Sync-DgSignInCertificate -Config $config | ForEach-Object { $_ | ConvertTo-Json -Compress }
