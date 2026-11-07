<#
.SYNOPSIS
    {{RunbookName}}: syncs the RDG definitions of the {{Provider}} group types.
.DESCRIPTION
    Azure Automation runbook (PowerShell 7.4). Generated from src/Runbooks/Sync-Groups.template.ps1
    by tools/Build-Runbook.ps1, which inlines the DgEngine module so this is a single file.
    Started by the tick schedules (Mode = Scheduled) and by the API's sync now (Mode = SyncNow
    with a DefinitionId). Settings come from Automation variables set by OpenTofu; none is a secret.
    The job fails only when a definition ended Blocked or Error (or the run itself failed).
#>
param(
    [ValidateSet('Scheduled', 'SyncNow')]
    [string] $Mode = 'Scheduled',

    [string] $DefinitionId
)

$ErrorActionPreference = 'Stop'

#{{DgEngine}}
if (-not (Get-Command -Name Invoke-DgSync -ErrorAction SilentlyContinue)) {
    # Unbuilt template (local development): load the module from the repo.
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../DgEngine/DgEngine.psd1')
}

$config = @{
    ClientId        = Get-AutomationVariable -Name 'DG_EngineClientId'
    TenantDomain    = Get-AutomationVariable -Name 'DG_TenantDomain'
    CosmosEndpoint  = Get-AutomationVariable -Name 'DG_CosmosEndpoint'
    CosmosDatabase  = Get-AutomationVariable -Name 'DG_CosmosDatabase'
    TickMinutes     = [int](Get-AutomationVariable -Name 'DG_TickMinutes')
    AccessMode      = Get-AutomationVariable -Name 'DG_AccessMode'
    MarkerExtension = Get-AutomationVariable -Name 'DG_MarkerExtension'
}

Invoke-DgSync -Provider '{{Provider}}' -Mode $Mode -DefinitionId $DefinitionId -Config $config | Write-DgRunbookResult
