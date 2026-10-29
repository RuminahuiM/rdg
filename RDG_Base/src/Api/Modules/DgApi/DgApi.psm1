#Requires -Version 7.4
Set-StrictMode -Version Latest

# The engine module: next to this one in the deployed package (Modules/DgEngine), or in the repo.
if (-not (Get-Module -Name DgEngine)) {
    $engine = @(
        (Join-Path -Path $PSScriptRoot -ChildPath '../DgEngine/DgEngine.psd1')
        (Join-Path -Path $PSScriptRoot -ChildPath '../../../DgEngine/DgEngine.psd1')
    ) | Where-Object { Test-Path -Path $_ } | Select-Object -First 1
    if (-not $engine) { throw 'DgEngine module not found next to DgApi' }
    Import-Module -Name $engine -Global
}

# Per worker: the API context (store, Graph, settings from app settings) and caches.
$script:DgApiContext = $null
$script:DgApiSchemas = @{}
$script:DgApiOpenApi = $null

$files = @(
    Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse -File | Sort-Object -Property FullName
    Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File | Sort-Object -Property FullName
)
foreach ($file in $files) {
    . $file.FullName
}
