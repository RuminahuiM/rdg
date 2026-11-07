#Requires -Version 7.4
<#
.SYNOPSIS
    Builds the Azure Automation runbooks: each one a single file with DgEngine inlined.
.DESCRIPTION
    Sync-EntraGroups.ps1 and Sync-ExchangeGroups.ps1 come from src/Runbooks/Sync-Groups.template.ps1;
    Renew-SignInCertificate.ps1 from its own source. The line "#{{DgEngine}}" is replaced by the
    module as a dynamic module (New-Module), with the same files in the same order as
    DgEngine.psm1 loads them, so private functions stay private. Automation then needs no custom
    module package and the engine version can't drift from the runbook.
    Every output file is parsed; a syntax error fails the build.
.EXAMPLE
    ./tools/Build-Runbook.ps1 -OutputPath ./out/runbooks
#>
[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../out/runbooks'),

    # Version stamped into the runbooks (Get-DgEngineVersion). Defaults to the manifest's
    # ModuleVersion plus PSData.Prerelease.
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$')]
    [string] $Version
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
$engine = Join-Path -Path $root -ChildPath 'src/DgEngine'
$runbooks = Join-Path -Path $root -ChildPath 'src/Runbooks'
$manifest = Import-PowerShellDataFile -Path (Join-Path -Path $engine -ChildPath 'DgEngine.psd1')
$version = if ($Version) { $Version } else {
    $prerelease = [string]$manifest.PrivateData.PSData['Prerelease']
    if ($prerelease) { "$($manifest.ModuleVersion)-$prerelease" } else { [string]$manifest.ModuleVersion }
}

# Same order as DgEngine.psm1: private files (recursively, by full name), then public.
$files = @(
    Get-ChildItem -Path (Join-Path -Path $engine -ChildPath 'Private') -Filter '*.ps1' -Recurse -File | Sort-Object -Property FullName
    Get-ChildItem -Path (Join-Path -Path $engine -ChildPath 'Public') -Filter '*.ps1' -File | Sort-Object -Property FullName
)
$body = [System.Text.StringBuilder]::new()
foreach ($file in $files) {
    $relative = [System.IO.Path]::GetRelativePath($engine, $file.FullName) -replace '\\', '/'
    [void]$body.AppendLine("# --- $relative")
    # Lines are copied unchanged (no re-indenting), so multi-line strings keep their content.
    foreach ($line in (Get-Content -Path $file.FullName)) {
        if ($line -match '^\s*#Requires') { continue }
        [void]$body.AppendLine($line)
    }
}
$exports = ($manifest.FunctionsToExport | ForEach-Object { "'$_'" }) -join ', '
$inline = @"
#region DgEngine $version (inlined by tools/Build-Runbook.ps1; edit src/DgEngine instead)
`$null = New-Module -Name DgEngine -ScriptBlock {
    Set-StrictMode -Version Latest
    `$script:DgEngineVersion = '$version'
$($body.ToString().TrimEnd())
    Export-ModuleMember -Function @($exports)
} | Import-Module -Force -DisableNameChecking
#endregion
"@

$targets = @(
    @{ Name = 'Sync-EntraGroups'; Source = 'Sync-Groups.template.ps1'; Provider = 'Entra' }
    @{ Name = 'Sync-ExchangeGroups'; Source = 'Sync-Groups.template.ps1'; Provider = 'Exchange' }
    @{ Name = 'Renew-SignInCertificate'; Source = 'Renew-SignInCertificate.ps1'; Provider = '' }
)
$null = New-Item -Path $OutputPath -ItemType Directory -Force
foreach ($target in $targets) {
    $text = Get-Content -Raw -Path (Join-Path -Path $runbooks -ChildPath $target.Source)
    if ($text -notmatch '(?m)^#\{\{DgEngine\}\}\r?$') { throw "$($target.Source) has no #{{DgEngine}} line" }
    $text = $text.Replace('{{RunbookName}}', $target.Name).Replace('{{Provider}}', $target.Provider)
    $text = [regex]::Replace($text, '(?m)^#\{\{DgEngine\}\}\r?$', { $inline.Replace("`r`n", "`n") })
    $path = Join-Path -Path $OutputPath -ChildPath "$($target.Name).ps1"
    [System.IO.File]::WriteAllText($path, $text.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "$($target.Name): $($errors[0].Message) (line $($errors[0].Extent.StartLineNumber))" }
    Write-Information -MessageData "Built $path (DgEngine $version)" -InformationAction Continue
}
