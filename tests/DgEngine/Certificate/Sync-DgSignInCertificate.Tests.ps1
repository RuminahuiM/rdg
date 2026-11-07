#Requires -Version 7.4
# Renewal of the sign-in app's certificate: add the new Key Vault certificate, drop expired keys,
# fail when the newest key expires within 21 days.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Writers/Fakes.ps1')

    # A self-signed certificate (public part, base64 DER) valid from $From to $To.
    function Get-TestCertificate {
        param([string] $Name, [datetime] $From, [datetime] $To)
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            "CN=$Name", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $certificate = $request.CreateSelfSigned([DateTimeOffset]$From, [DateTimeOffset]$To)
        [pscustomobject]@{ Base64 = [System.Convert]::ToBase64String($certificate.RawData); Thumbprint = $certificate.Thumbprint; From = $From; To = $To; Name = "CN=$Name" }
    }

    function Get-KeyCredential {
        param($Certificate, [string] $KeyId)
        @{
            keyId = $KeyId; type = 'AsymmetricX509Cert'; usage = 'Verify'; key = $Certificate.Base64; displayName = $Certificate.Name
            startDateTime = $Certificate.From.ToString('o'); endDateTime = $Certificate.To.ToString('o')
        }
    }

    # Runs the renewal against a fake Graph holding $Keys and a fake Key Vault holding $Vault.
    function Invoke-Renewal {
        param([object[]] $Keys, $Vault, [string] $Now = '2026-10-12T08:00:00Z')
        $state = @{ Keys = $Keys }
        $fake = Get-FakeGraph -Handler {
            param($Call)
            if ($Call.Method -eq 'GET') { return @{ id = 'app-object-1'; keyCredentials = $state.Keys } }
            $null
        }.GetNewClosure()
        $vaultCer = $Vault.Base64
        $keyVault = InModuleScope DgEngine -Parameters @{ C = $vaultCer } {
            New-DgKeyVault -VaultUri 'https://rdg-contoso-kv.vault.azure.net' -Request { param($Path) @{ cer = $C; id = "https://rdg-contoso-kv.vault.azure.net$Path" } }.GetNewClosure()
        }
        $outcome = [ordered]@{ Result = $null; Error = $null; Calls = $fake.State.Calls }
        try {
            $outcome.Result = Sync-DgSignInCertificate -Graph $fake.Directory -KeyVault $keyVault -CertificateName 'rdg-signin' `
                -SignInAppId '00000000-0000-4000-a000-000000000001' -Now ([DateTimeOffset]$Now)
        } catch {
            $outcome.Error = $_.Exception.Message
        }
        [pscustomobject]$outcome
    }
}

Describe 'Sync-DgSignInCertificate' {
    It 'adds the renewed Key Vault certificate and keeps the current key' {
        $current = Get-TestCertificate -Name 'rdg-2026' -From '2026-01-01' -To '2026-12-31'
        $renewed = Get-TestCertificate -Name 'rdg-2027' -From '2026-10-01' -To '2027-10-01'
        $run = Invoke-Renewal -Keys @(Get-KeyCredential $current 'k1') -Vault $renewed

        $run.Error | Should -BeNullOrEmpty
        $run.Result.Added | Should -Be $renewed.Thumbprint
        $patch = $run.Calls | Where-Object { $_.Method -eq 'PATCH' }
        $patch.Uri | Should -BeLike '*/applications/app-object-1'
        $keys = $patch.Body.keyCredentials
        $keys | Should -HaveCount 2
        $keys[0].keyId | Should -Be 'k1'
        $keys[0].key | Should -Be $current.Base64
        $keys[1].key | Should -Be $renewed.Base64
        $keys[1].type | Should -Be 'AsymmetricX509Cert'
        $keys[1].usage | Should -Be 'Verify'
        $keys[1].Contains('keyId') | Should -BeFalse
        $run.Calls[0].Uri | Should -BeLike "*/applications(appId='00000000-0000-4000-a000-000000000001')?`$select=id,keyCredentials"
    }

    It 'removes expired keys' {
        $expired = Get-TestCertificate -Name 'rdg-2025' -From '2025-01-01' -To '2026-01-01'
        $current = Get-TestCertificate -Name 'rdg-2026' -From '2026-01-01' -To '2026-12-31'
        $run = Invoke-Renewal -Keys @((Get-KeyCredential $expired 'k0'), (Get-KeyCredential $current 'k1')) -Vault $current

        $run.Error | Should -BeNullOrEmpty
        $run.Result.Added | Should -BeNullOrEmpty
        ($run.Result.Removed -join ',') | Should -Be $expired.Thumbprint
        $keys = ($run.Calls | Where-Object { $_.Method -eq 'PATCH' }).Body.keyCredentials
        @($keys) | Should -HaveCount 1
        $keys[0].keyId | Should -Be 'k1'
    }

    It 'changes nothing when the app is up to date' {
        $current = Get-TestCertificate -Name 'rdg-2026' -From '2026-01-01' -To '2026-12-31'
        $run = Invoke-Renewal -Keys @(Get-KeyCredential $current 'k1') -Vault $current
        $run.Error | Should -BeNullOrEmpty
        $run.Result.Changed | Should -BeFalse
        @($run.Calls | Where-Object { $_.Method -eq 'PATCH' }) | Should -HaveCount 0
    }

    It 'fails on purpose when the newest key expires within 21 days' {
        $current = Get-TestCertificate -Name 'rdg-2026' -From '2026-01-01' -To '2026-10-30'
        $run = Invoke-Renewal -Keys @(Get-KeyCredential $current 'k1') -Vault $current
        $run.Error | Should -BeLike '*newest key*expires on 2026-10-30*within 21 days*'
    }

    It 'still adds the renewed certificate before checking the expiry' {
        $current = Get-TestCertificate -Name 'rdg-2026' -From '2026-01-01' -To '2026-10-30'
        $renewed = Get-TestCertificate -Name 'rdg-2027' -From '2026-10-01' -To '2027-10-01'
        $run = Invoke-Renewal -Keys @(Get-KeyCredential $current 'k1') -Vault $renewed
        $run.Error | Should -BeNullOrEmpty
        @($run.Calls | Where-Object { $_.Method -eq 'PATCH' }) | Should -HaveCount 1
    }

    It 'refuses to write when a kept key came back without its value' {
        $current = Get-TestCertificate -Name 'rdg-2026' -From '2026-01-01' -To '2026-12-31'
        $renewed = Get-TestCertificate -Name 'rdg-2027' -From '2026-10-01' -To '2027-10-01'
        $credential = Get-KeyCredential $current 'k1'
        $credential.key = $null
        $run = Invoke-Renewal -Keys @($credential) -Vault $renewed
        $run.Error | Should -BeLike '*without its value*'
        @($run.Calls | Where-Object { $_.Method -eq 'PATCH' }) | Should -HaveCount 0
    }
}
