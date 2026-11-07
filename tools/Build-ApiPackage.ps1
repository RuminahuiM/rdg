#Requires -Version 7.4
<#
.SYNOPSIS
    Builds the Function App package: api-<version>.zip with DgApi and DgEngine in Modules/.
.DESCRIPTION
    Copies src/Api (functions, host.json, profile.ps1, Modules/DgApi) and src/DgEngine into a
    staging folder and zips it. Microsoft.Graph.Authentication is added from -GraphModulePath (the
    pipeline saves the pinned version there); without it the package can only run the endpoints
    that don't need Graph.
    -Local instead copies DgEngine into src/Api/Modules (ignored by git), so `func start` works in
    src/Api for local runs with Azure Functions Core Tools.
.EXAMPLE
    ./tools/Build-ApiPackage.ps1 -OutputPath ./out -GraphModulePath ./out/modules/Microsoft.Graph.Authentication
.EXAMPLE
    ./tools/Build-ApiPackage.ps1 -Local
#>
[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../out'),

    [string] $GraphModulePath,

    [switch] $Local
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
$api = Join-Path -Path $root -ChildPath 'src/Api'
$engine = Join-Path -Path $root -ChildPath 'src/DgEngine'
$version = [string](Import-PowerShellDataFile -Path (Join-Path -Path $engine -ChildPath 'DgEngine.psd1')).ModuleVersion

$copyEngine = {
    param([string] $Destination)
    $null = New-Item -Path $Destination -ItemType Directory -Force
    Copy-Item -Path (Join-Path $engine 'DgEngine.psd1'), (Join-Path $engine 'DgEngine.psm1') -Destination $Destination
    Copy-Item -Path (Join-Path $engine 'Private'), (Join-Path $engine 'Public') -Destination $Destination -Recurse
}

if ($Local) {
    $target = Join-Path -Path $api -ChildPath 'Modules/DgEngine'
    if (Test-Path -Path $target) { Remove-Item -Path $target -Recurse -Force }
    & $copyEngine $target
    Write-Information -MessageData "DgEngine $version copied to src/Api/Modules for func start" -InformationAction Continue
    return
}

$staging = Join-Path -Path $OutputPath -ChildPath 'api'
if (Test-Path -Path $staging) { Remove-Item -Path $staging -Recurse -Force }
$null = New-Item -Path $staging -ItemType Directory -Force
$excluded = @('openapi.yaml', 'README.md', 'local.settings.example.json', 'local.settings.json', '.funcignore')
foreach ($item in Get-ChildItem -Path $api -Force) {
    if ($item.Name -in $excluded -or $item.Name -eq 'Modules') { continue }
    Copy-Item -Path $item.FullName -Destination $staging -Recurse
}
$modules = Join-Path -Path $staging -ChildPath 'Modules'
$null = New-Item -Path $modules -ItemType Directory -Force
Copy-Item -Path (Join-Path $api 'Modules/DgApi') -Destination $modules -Recurse
& $copyEngine (Join-Path -Path $modules -ChildPath 'DgEngine')
if ($GraphModulePath) {
    Copy-Item -Path $GraphModulePath -Destination (Join-Path -Path $modules -ChildPath 'Microsoft.Graph.Authentication') -Recurse
} else {
    Write-Warning -Message 'No -GraphModulePath: the package has no Microsoft.Graph.Authentication module.'
}
$zip = Join-Path -Path $OutputPath -ChildPath "api-$version.zip"
if (Test-Path -Path $zip) { Remove-Item -Path $zip -Force }
Compress-Archive -Path (Join-Path -Path $staging -ChildPath '*') -DestinationPath $zip
Write-Information -MessageData "Built $zip" -InformationAction Continue
