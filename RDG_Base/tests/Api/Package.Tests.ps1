#Requires -Version 7.4
# tools/Build-ApiPackage.ps1 produces a Function App package that loads.

Describe 'Build-ApiPackage' {
    It 'packages functions, host.json and both modules, and the package module loads' {
        $out = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "rdg-api-$([guid]::NewGuid())"
        try {
            & (Join-Path -Path $PSScriptRoot -ChildPath '../../tools/Build-ApiPackage.ps1') -OutputPath $out -WarningAction SilentlyContinue -InformationAction SilentlyContinue
            Test-Path -Path (Join-Path $out 'api-0.1.0.zip') | Should -BeTrue
            $staging = Join-Path $out 'api'
            foreach ($path in @('host.json', 'profile.ps1', 'me/function.json', 'definitions/run.ps1', 'Modules/DgApi/openapi.json', 'Modules/DgEngine/DgEngine.psd1', 'Modules/DgEngine/Public/Invoke-DgSync.ps1', 'Modules/DgEngine/Private/Sync/Invoke-DgDefinitionSync.ps1')) {
                Test-Path -Path (Join-Path $staging $path) | Should -BeTrue -Because $path
            }
            Test-Path -Path (Join-Path $staging 'openapi.yaml') | Should -BeFalse
            $pwsh = (Get-Process -Id $PID).Path
            $loaded = & $pwsh -NoProfile -NonInteractive -Command "`$env:PSModulePath = '$(Join-Path $staging 'Modules')' + [IO.Path]::PathSeparator + `$env:PSModulePath; Import-Module DgApi; (Get-Module DgEngine).Path"
            $loaded | Should -BeLike "*$([IO.Path]::DirectorySeparatorChar)api$([IO.Path]::DirectorySeparatorChar)Modules*"
        } finally {
            Remove-Item -Path $out -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
