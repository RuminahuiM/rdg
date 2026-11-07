#Requires -Version 7.4
<#
.SYNOPSIS
    Writes the rule property list the web app's editor uses (autocomplete, highlighting).
.DESCRIPTION
    Reads the engine's property map (Get-DgPropertyMap) and writes name and type of every
    property, sorted by name, to src/Web/src/rules/properties.json. The editor then offers
    exactly the properties the engine understands. A Pester test fails when the file is out of
    date, so run this after changing the property map.
.EXAMPLE
    ./tools/Export-RuleProperties.ps1
#>
[CmdletBinding()]
param(
    [string] $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../src/Web/src/rules/properties.json'),

    # Returns the JSON text instead of writing it (used by the test).
    [switch] $PassThru
)

$ErrorActionPreference = 'Stop'
$manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/DgEngine/DgEngine.psd1'
$module = Import-Module -Name $manifest -Force -PassThru
$map = & $module { Get-DgPropertyMap }

$properties = foreach ($entry in $map.Values | Sort-Object -Property Name) {
    [ordered]@{ name = $entry.Name; type = $entry.Type }
}
$document = [ordered]@{
    generatedBy = 'tools/Export-RuleProperties.ps1'
    properties  = @($properties)
}
$json = ($document | ConvertTo-Json -Depth 4) -replace "`r`n", "`n"

if ($PassThru) {
    return $json
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json + "`n", [Text.UTF8Encoding]::new($false))
