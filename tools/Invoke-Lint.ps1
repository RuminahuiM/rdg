#Requires -Version 7.4
<#
.SYNOPSIS
    Runs PSScriptAnalyzer on every PowerShell file in the repo.
.DESCRIPTION
    Same check as the "powershell" job in CI, so it can be run locally before a push.
    Installs the pinned PSScriptAnalyzer version for the current user if it is missing.
    Exits with code 1 when any Error or Warning is found.
.EXAMPLE
    ./tools/Invoke-Lint.ps1
#>
[CmdletBinding()]
param(
    # Folder to analyse. Defaults to the repo root.
    [string] $Path = (Join-Path -Path $PSScriptRoot -ChildPath '..')
)

$ErrorActionPreference = 'Stop'
# renovate: datasource=nuget registryUrl=https://www.powershellgallery.com/api/v2 depName=PSScriptAnalyzer
$analyzerVersion = '1.23.0'

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer | Where-Object Version -EQ $analyzerVersion)) {
    Write-Information -MessageData "Installing PSScriptAnalyzer $analyzerVersion" -InformationAction Continue
    Install-Module -Name PSScriptAnalyzer -RequiredVersion $analyzerVersion -Scope CurrentUser -Force
}
Import-Module -Name PSScriptAnalyzer -RequiredVersion $analyzerVersion

$root = Resolve-Path -Path $Path
$settings = Join-Path -Path $root -ChildPath 'PSScriptAnalyzerSettings.psd1'

$results = Invoke-ScriptAnalyzer -Path $root -Recurse -Settings $settings

if ($results) {
    $results | Sort-Object -Property ScriptPath, Line |
        Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize -Wrap
    Write-Error -Message "PSScriptAnalyzer found $(@($results).Count) issue(s)." -ErrorAction Continue
    exit 1
}

Write-Information -MessageData 'PSScriptAnalyzer: no issues.' -InformationAction Continue
