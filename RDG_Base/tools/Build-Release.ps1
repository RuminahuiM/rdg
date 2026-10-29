#Requires -Version 7.4
<#
.SYNOPSIS
    Builds the release bundle rdg-<version>.zip and SHA256SUMS.
.DESCRIPTION
    The bundle is everything an installation deploys (CI/CD design, "Release"):
      VERSION
      runbooks/   Sync-EntraGroups.ps1, Sync-ExchangeGroups.ps1, Renew-SignInCertificate.ps1
      api/        api.zip (Function App package with DgApi, DgEngine and Microsoft.Graph.Authentication)
      web/        the built web app (src/Web/dist)
      infra/      OpenTofu configuration
      bootstrap/  stage 1 and 2 scripts
      deploy/     the pipeline template and Deploy-Rdg.ps1
      examples/   the example settings file
    The version is stamped into a copy of DgEngine (ModuleVersion and PSData.Prerelease), so the
    runbooks, the API (/api/health) and every run record report it. The working tree is not
    changed.
.PARAMETER Version
    Semantic version without the leading v, for example 1.2.0 or 1.3.0-rc.1.
.PARAMETER WebDistPath
    Built web app (npm run build in src/Web). Required unless -SkipWeb.
.PARAMETER GraphModulePath
    Saved Microsoft.Graph.Authentication module for the API package.
.EXAMPLE
    ./tools/Build-Release.ps1 -Version 1.0.0 -GraphModulePath ./out/modules/Microsoft.Graph.Authentication
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$')]
    [string] $Version,

    [string] $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../out/release'),

    [string] $WebDistPath = (Join-Path -Path $PSScriptRoot -ChildPath '../src/Web/dist'),

    [string] $GraphModulePath,

    # For tests and local checks: no web app in the bundle.
    [switch] $SkipWeb
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
$core, $prerelease = $Version -split '-', 2

$null = New-Item -Path $OutputPath -ItemType Directory -Force
$OutputPath = (Resolve-Path -Path $OutputPath).Path
$work = Join-Path -Path $OutputPath -ChildPath 'work'
$bundle = Join-Path -Path $work -ChildPath "rdg-$Version"
if (Test-Path -Path $work) { Remove-Item -Path $work -Recurse -Force }
$null = New-Item -Path $bundle -ItemType Directory -Force

# 1. A copy of the sources the builds need, with the version stamped into DgEngine.
$source = Join-Path -Path $work -ChildPath 'source'
foreach ($relative in @('src/DgEngine', 'src/Runbooks', 'src/Api', 'tools/Build-Runbook.ps1', 'tools/Build-ApiPackage.ps1')) {
    $target = Join-Path -Path $source -ChildPath $relative
    $null = New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force
    Copy-Item -Path (Join-Path -Path $root -ChildPath $relative) -Destination $target -Recurse
}
foreach ($leftover in @('src/Api/Modules/DgEngine', 'src/Api/Modules/Microsoft.Graph.Authentication')) {
    $path = Join-Path -Path $source -ChildPath $leftover
    if (Test-Path -Path $path) { Remove-Item -Path $path -Recurse -Force }   # from Build-ApiPackage.ps1 -Local
}
$manifest = Join-Path -Path $source -ChildPath 'src/DgEngine/DgEngine.psd1'
$text = Get-Content -Raw -Path $manifest
$text = [regex]::Replace($text, "(?m)^(\s*ModuleVersion\s*=\s*)'[^']*'", "`${1}'$core'")
$text = [regex]::Replace($text, "(?m)^\s*Prerelease\s*=.*\r?\n", '')
if ($prerelease) {
    if ($text -notmatch '(?m)^(\s*)PSData\s*=\s*@\{') { throw 'DgEngine.psd1 has no PSData block to stamp the prerelease into' }
    $text = [regex]::Replace($text, '(?m)^(\s*)PSData\s*=\s*@\{\r?\n', { param($m) "$($m.Value)$($m.Groups[1].Value)    Prerelease = '$prerelease'`n" })
}
Set-Content -Path $manifest -Value $text -NoNewline
$stamped = Import-PowerShellDataFile -Path $manifest
if ([string]$stamped.ModuleVersion -ne $core -or [string]$stamped.PrivateData.PSData['Prerelease'] -ne [string]$prerelease) {
    throw "stamping DgEngine.psd1 with $Version failed"
}

# 2. Runbooks and the API package, built from the stamped copy.
& (Join-Path -Path $source -ChildPath 'tools/Build-Runbook.ps1') -OutputPath (Join-Path -Path $bundle -ChildPath 'runbooks') -Version $Version
$apiWork = Join-Path -Path $work -ChildPath 'api-build'
$apiArguments = @{ OutputPath = $apiWork }
if ($GraphModulePath) { $apiArguments.GraphModulePath = (Resolve-Path -Path $GraphModulePath).Path }
& (Join-Path -Path $source -ChildPath 'tools/Build-ApiPackage.ps1') @apiArguments
$null = New-Item -Path (Join-Path -Path $bundle -ChildPath 'api') -ItemType Directory
Move-Item -Path (Join-Path -Path $apiWork -ChildPath "api-$core.zip") -Destination (Join-Path -Path $bundle -ChildPath 'api/api.zip')

# 3. Web app.
if (-not $SkipWeb) {
    if (-not (Test-Path -Path (Join-Path -Path $WebDistPath -ChildPath 'index.html'))) { throw "no built web app in $WebDistPath; run npm run build in src/Web" }
    if (-not (Test-Path -Path (Join-Path -Path $WebDistPath -ChildPath 'staticwebapp.config.json'))) { throw 'the web build has no staticwebapp.config.json' }
    Copy-Item -Path $WebDistPath -Destination (Join-Path -Path $bundle -ChildPath 'web') -Recurse
}

# 4. Configuration and scripts as they are.
foreach ($folder in @('infra', 'bootstrap', 'deploy', 'examples')) {
    $target = Join-Path -Path $bundle -ChildPath $folder
    Copy-Item -Path (Join-Path -Path $root -ChildPath $folder) -Destination $target -Recurse
    Get-ChildItem -Path $target -Recurse -Force -Directory -Filter '.terraform' | Remove-Item -Recurse -Force
    Get-ChildItem -Path $target -Recurse -Force -File | Where-Object { $_.Name -like '*.tfstate*' -or $_.Name -like '*.tfplan' } | Remove-Item -Force
}
Set-Content -Path (Join-Path -Path $bundle -ChildPath 'VERSION') -Value $Version -NoNewline

# 5. Zip and checksum.
$zip = Join-Path -Path $OutputPath -ChildPath "rdg-$Version.zip"
if (Test-Path -Path $zip) { Remove-Item -Path $zip -Force }
# ZipFile instead of Compress-Archive: Compress-Archive leaves out dot files such as
# infra/.terraform.lock.hcl.
[System.IO.Compression.ZipFile]::CreateFromDirectory($bundle, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
$hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$sums = Join-Path -Path $OutputPath -ChildPath 'SHA256SUMS'
Set-Content -Path $sums -Value "$hash  rdg-$Version.zip`n" -NoNewline
Remove-Item -Path $work -Recurse -Force

Write-Information -MessageData "Built $zip ($hash)" -InformationAction Continue
[pscustomobject]@{ Version = $Version; Bundle = $zip; Sha256 = $hash; Sums = $sums }
