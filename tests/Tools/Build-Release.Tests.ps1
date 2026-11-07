#Requires -Version 7.4
# The release bundle: layout, version stamp in runbooks and API, checksum, untouched sources.

BeforeAll {
    function Get-TestBundle {
        # Builds once per test run (a few seconds) and unpacks the bundle and its API package.
        if (-not $script:TestBundle) {
            $out = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "rdg-release-$([guid]::NewGuid())"
            $result = & (Join-Path -Path $PSScriptRoot -ChildPath '../../tools/Build-Release.ps1') -Version '9.8.7-rc.1' -SkipWeb -OutputPath $out -WarningAction SilentlyContinue
            $unpacked = Join-Path -Path $out -ChildPath 'unpacked'
            Expand-Archive -Path $result.Bundle -DestinationPath $unpacked
            Expand-Archive -Path (Join-Path -Path $unpacked -ChildPath 'api/api.zip') -DestinationPath (Join-Path -Path $out -ChildPath 'api')
            $script:TestBundle = [pscustomobject]@{ Out = $out; Result = $result; Path = $unpacked; Api = (Join-Path -Path $out -ChildPath 'api') }
        }
        $script:TestBundle
    }
}

AfterAll {
    if ($script:TestBundle) { Remove-Item -Path $script:TestBundle.Out -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Build-Release.ps1' {
    It 'packs runbooks, the API package, infra, bootstrap, deploy, examples and VERSION' {
        $bundle = Get-TestBundle
        (Get-Content -Raw -Path (Join-Path $bundle.Path 'VERSION')) | Should -BeExactly '9.8.7-rc.1'
        foreach ($name in @('Sync-EntraGroups', 'Sync-ExchangeGroups', 'Renew-SignInCertificate')) {
            Test-Path -Path (Join-Path $bundle.Path "runbooks/$name.ps1") | Should -BeTrue
        }
        foreach ($path in @('api/api.zip', 'infra/main.tf', 'infra/.terraform.lock.hcl', 'bootstrap/Initialize-RdgTenant.ps1', 'deploy/Deploy-Rdg.ps1', 'deploy/azure-pipelines.yml', 'examples/contoso.tfvars')) {
            Test-Path -Path (Join-Path $bundle.Path $path) | Should -BeTrue -Because $path
        }
        @(Get-ChildItem -Path $bundle.Path -Recurse -Force -Directory -Filter '.terraform') | Should -HaveCount 0
    }

    It 'stamps the full version into the runbooks' {
        $text = Get-Content -Raw -Path (Join-Path (Get-TestBundle).Path 'runbooks/Sync-EntraGroups.ps1')
        $text | Should -BeLike "*`$script:DgEngineVersion = '9.8.7-rc.1'*"
    }

    It 'stamps DgEngine in the API package, so /api/health reports the full version' {
        $manifest = Join-Path (Get-TestBundle).Api 'Modules/DgEngine/DgEngine.psd1'
        $data = Import-PowerShellDataFile -Path $manifest
        $data.ModuleVersion | Should -BeExactly '9.8.7'
        $data.PrivateData.PSData.Prerelease | Should -BeExactly 'rc.1'
        $reported = & (Get-Process -Id $PID).Path -NoProfile -Command "Import-Module '$manifest'; Get-DgEngineVersion"
        $reported | Should -BeExactly '9.8.7-rc.1'
        Test-Path -Path (Join-Path (Get-TestBundle).Api 'Modules/DgApi') | Should -BeTrue
        Test-Path -Path (Join-Path (Get-TestBundle).Api 'host.json') | Should -BeTrue
    }

    It 'writes SHA256SUMS for the zip' {
        $bundle = Get-TestBundle
        $line = Get-Content -Raw -Path $bundle.Result.Sums
        $hash = (Get-FileHash -Path $bundle.Result.Bundle -Algorithm SHA256).Hash.ToLowerInvariant()
        $line | Should -BeExactly "$hash  rdg-9.8.7-rc.1.zip`n"
    }

    It 'leaves the working tree unchanged' {
        $null = Get-TestBundle
        $source = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '../../src/DgEngine/DgEngine.psd1')
        $source.ModuleVersion | Should -Not -Be '9.8.7'
    }

    It 'refuses a version that is not semantic' {
        { & (Join-Path -Path $PSScriptRoot -ChildPath '../../tools/Build-Release.ps1') -Version 'v1.0' -SkipWeb -OutputPath ([System.IO.Path]::GetTempPath()) } | Should -Throw
    }
}
