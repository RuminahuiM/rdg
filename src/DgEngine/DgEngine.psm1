#Requires -Version 7.4
Set-StrictMode -Version Latest

# Private helpers first (recursively, by area), then the public functions.
# The runbook build inlines these same files in the same order.
$privateFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse -File |
    Sort-Object -Property FullName
$publicFiles = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File |
    Sort-Object -Property FullName

foreach ($file in @($privateFiles) + @($publicFiles)) {
    . $file.FullName
}
