#Requires -Version 7.4
# The built runbooks (tools/Build-Runbook.ps1), run in a fake Automation sandbox: every service
# call goes through the engine's real code paths against fakes (Harness/Invoke-RunbookHarness.ps1).

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../src/DgEngine/DgEngine.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath '../DgEngine/Sync/SyncTestKit.ps1')

    $script:BuildDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "rdg-runbooks-$([guid]::NewGuid())"
    & (Join-Path -Path $PSScriptRoot -ChildPath '../../tools/Build-Runbook.ps1') -OutputPath $script:BuildDir -InformationAction SilentlyContinue
    $script:Harness = Join-Path -Path $PSScriptRoot -ChildPath 'Harness/Invoke-RunbookHarness.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path

    $script:EngineClient = '00000000-0000-4000-b000-000000000001'
    $script:MaintenanceClient = '00000000-0000-4000-b000-000000000002'
    $script:AppId = '00000000-0000-4000-a000-000000000001'

    function Get-EngineVariable {
        param([string] $AccessMode = 'read-write')
        @{
            DG_EngineClientId = $script:EngineClient; DG_TenantDomain = 'contoso.onmicrosoft.com'
            DG_CosmosEndpoint = 'https://rdg-contoso.documents.azure.com'; DG_CosmosDatabase = 'rdg'
            DG_TickMinutes = '15'; DG_AccessMode = $AccessMode; DG_MarkerExtension = ''
        }
    }

    # The Cosmos containers as the fake keeps them: container -> "pk|id" -> document.
    function Get-CosmosState {
        param([object[]] $Config, [object[]] $State = @())
        $cosmos = @{ config = @{}; state = @{}; runs = @{} }
        foreach ($document in $Config) { $cosmos.config["$($document['pk'])|$($document['id'])"] = $document }
        foreach ($document in $State) { $cosmos.state["$($document['pk'])|$($document['id'])"] = $document }
        $cosmos
    }

    function Invoke-Runbook {
        param([string] $Name, [hashtable] $State, [hashtable] $Arguments = @{})
        $path = Join-Path -Path $script:BuildDir -ChildPath "state-$([guid]::NewGuid()).json"
        $State | ConvertTo-Json -Depth 30 | Set-Content -Path $path -Encoding utf8NoBOM
        $runbook = Join-Path -Path $script:BuildDir -ChildPath "$Name.ps1"
        $console = & $script:Pwsh -NoProfile -NonInteractive -File $script:Harness -Runbook $runbook -StatePath $path -ArgumentsJson ($Arguments | ConvertTo-Json -Compress) 2>&1
        if ($LASTEXITCODE -ne 0) { throw "harness failed: $console" }
        Get-Content -Raw -Path $path | ConvertFrom-Json -AsHashtable
    }

    function Get-SignInCertificate {
        param([int] $FromDays, [int] $ToDays, [string] $Name)
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            "CN=$Name", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $now = [DateTimeOffset]::UtcNow
        $certificate = $request.CreateSelfSigned($now.AddDays($FromDays), $now.AddDays($ToDays))
        @{
            Base64 = [System.Convert]::ToBase64String($certificate.RawData); Thumbprint = $certificate.Thumbprint
            From = $now.AddDays($FromDays).ToString('o'); To = $now.AddDays($ToDays).ToString('o'); Name = "CN=$Name"
        }
    }
}

AfterAll {
    if ($script:BuildDir -and (Test-Path -Path $script:BuildDir)) { Remove-Item -Path $script:BuildDir -Recurse -Force }
}

Describe 'Build-Runbook' {
    It 'builds the three runbooks as single files that parse' {
        foreach ($name in @('Sync-EntraGroups', 'Sync-ExchangeGroups', 'Renew-SignInCertificate')) {
            $path = Join-Path -Path $script:BuildDir -ChildPath "$name.ps1"
            Test-Path -Path $path | Should -BeTrue
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
            $errors | Should -HaveCount 0
            $ast.ParamBlock | Should -Not -BeNullOrEmpty
            $text = Get-Content -Raw -Path $path
            $text | Should -Not -BeLike '*#Requires*'
            $text | Should -Not -BeLike '*{{*'
            $text | Should -BeLike "*`$script:DgEngineVersion = '0.1.0'*"
        }
    }

    It 'inlines every engine file once' {
        $text = Get-Content -Raw -Path (Join-Path -Path $script:BuildDir -ChildPath 'Sync-EntraGroups.ps1')
        $files = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../src/DgEngine') -Filter '*.ps1' -Recurse -File
        foreach ($file in $files) {
            ([regex]::Matches($text, "(?m)^function $([regex]::Escape($file.BaseName)) \{")).Count | Should -Be 1 -Because $file.Name
        }
    }

    It 'sets the provider per sync runbook' {
        (Get-Content -Raw -Path (Join-Path $script:BuildDir 'Sync-EntraGroups.ps1')) | Should -BeLike "*Invoke-DgSync -Provider 'Entra'*"
        (Get-Content -Raw -Path (Join-Path $script:BuildDir 'Sync-ExchangeGroups.ps1')) | Should -BeLike "*Invoke-DgSync -Provider 'Exchange'*"
    }
}

Describe 'Sync-EntraGroups (built)' {
    It 'connects as the engine identity, syncs the group and reports one line per definition' {
        $users = @((Get-TestUser 1), (Get-TestUser 2), (Get-TestUser 4 -Department 'Finance'))
        $state = @{
            Variables = Get-EngineVariable
            Users     = $users
            Groups    = @{ (Get-TestGroupId 1) = @{ displayName = 'Sales'; groupTypes = @(); members = @(Get-TestUserId 4) } }
            Cosmos    = Get-CosmosState -Config @((Get-TestSettingDocument), (Get-TestDefinition)) -State @(Get-TestStatus -LastSyncUtc '2026-01-01T00:00:00.000Z')
        }
        $result = Invoke-Runbook -Name 'Sync-EntraGroups' -State $state

        $result.Error | Should -BeNullOrEmpty
        $result.Output | Should -HaveCount 2
        $line = $result.Output[0] | ConvertFrom-Json
        $line.definition | Should -Be 'Definition 1'
        $line.result | Should -Be 'OK'
        $line.added | Should -Be 2
        $line.removed | Should -Be 1
        ($result.Output[1] | ConvertFrom-Json).result | Should -Be 'Succeeded'
        (@($result.Groups[(Get-TestGroupId 1)].members) | Sort-Object) -join ',' | Should -Be ((Get-TestUserId 1), (Get-TestUserId 2) -join ',')
        $result.Calls | Should -Contain "Connect-MgGraph $script:EngineClient"
        $result.Calls | Should -Contain "token https://rdg-contoso.documents.azure.com $script:EngineClient"
        @($result.Cosmos.runs) | Should -HaveCount 1
        @($result.Cosmos.state | Where-Object { $_['type'] -eq 'lock' }) | Should -HaveCount 0
        (@($result.Cosmos.state | Where-Object { $_['type'] -eq 'heartbeat' }))[0]['userCount'] | Should -Be 3
    }

    It 'fails the job with one summary error when a definition is blocked' {
        $state = @{
            Variables = Get-EngineVariable
            Users     = @((Get-TestUser 1))
            Groups    = @{ (Get-TestGroupId 1) = @{ displayName = 'Synced'; groupTypes = @(); members = @(); onPremisesSyncEnabled = $true } }
            Cosmos    = Get-CosmosState -Config @((Get-TestSettingDocument), (Get-TestDefinition)) -State @(Get-TestStatus -LastSyncUtc '2026-01-01T00:00:00.000Z')
        }
        $result = Invoke-Runbook -Name 'Sync-EntraGroups' -State $state
        $result.Error | Should -BeLike '1 definitions blocked or failed: Definition 1 (Blocked: the group is synced from on-premises AD*'
        $result.Warnings | Should -Contain 'Definition 1: the group is synced from on-premises AD; RDG cannot manage it'
        ($result.Output[0] | ConvertFrom-Json).result | Should -Be 'Blocked'
    }

    It 'runs read-only when the access mode says so' {
        $state = @{
            Variables = Get-EngineVariable -AccessMode 'read-only'
            Users     = @((Get-TestUser 1))
            Groups    = @{ (Get-TestGroupId 1) = @{ displayName = 'Sales'; groupTypes = @(); members = @() } }
            Cosmos    = Get-CosmosState -Config @((Get-TestSettingDocument), (Get-TestDefinition)) -State @(Get-TestStatus -LastSyncUtc '2026-01-01T00:00:00.000Z')
        }
        $result = Invoke-Runbook -Name 'Sync-EntraGroups' -State $state
        $result.Error | Should -BeNullOrEmpty
        ($result.Output[0] | ConvertFrom-Json).result | Should -Be 'DryRun'
        @($result.Groups[(Get-TestGroupId 1)].members) | Should -HaveCount 0
    }

    It 'takes Mode and DefinitionId from the job parameters' {
        $state = @{
            Variables = Get-EngineVariable
            Users     = @((Get-TestUser 1))
            Groups    = @{ (Get-TestGroupId 1) = @{ displayName = 'Sales'; groupTypes = @(); members = @() } }
            Cosmos    = Get-CosmosState -Config @((Get-TestSettingDocument), (Get-TestDefinition -Change @{ frequencyMinutes = 1440 })) `
                -State @(Get-TestStatus -LastSyncUtc ([DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')))
        }
        $result = Invoke-Runbook -Name 'Sync-EntraGroups' -State $state -Arguments @{ Mode = 'SyncNow'; DefinitionId = (Get-TestDefinitionId 1) }
        $result.Error | Should -BeNullOrEmpty
        ($result.Output[-1] | ConvertFrom-Json).mode | Should -Be 'SyncNow'
        @($result.Groups[(Get-TestGroupId 1)].members) | Should -HaveCount 1
    }

    It 'fails before doing anything when an Automation variable is missing' {
        $variables = Get-EngineVariable
        $variables.Remove('DG_CosmosEndpoint')
        $result = Invoke-Runbook -Name 'Sync-EntraGroups' -State @{ Variables = $variables }
        $result.Error | Should -BeLike "*DG_CosmosEndpoint*not found*"
        $result.Calls | Should -HaveCount 0
    }
}

Describe 'Sync-ExchangeGroups (built)' {
    It 'connects to Exchange as the engine identity and adds only users with a mailbox' {
        $state = @{
            Variables  = Get-EngineVariable
            Users      = @((Get-TestUser 1), (Get-TestUser 2))
            Groups     = @{ (Get-TestGroupId 1) = @{ displayName = 'Sales list'; groupTypes = @(); members = @() } }
            Recipients = @{ (Get-TestUserId 1) = 'recipient-guid-1' }
            Cosmos     = Get-CosmosState -Config @((Get-TestSettingDocument), (Get-TestDefinition -GroupType Distribution)) -State @(Get-TestStatus -LastSyncUtc '2026-01-01T00:00:00.000Z')
        }
        $result = Invoke-Runbook -Name 'Sync-ExchangeGroups' -State $state
        $result.Error | Should -BeNullOrEmpty
        $result.Calls | Should -Contain "Connect-ExchangeOnline contoso.onmicrosoft.com $script:EngineClient"
        $result.Calls | Should -Contain "exchange add $(Get-TestUserId 1)"
        @($result.Groups[(Get-TestGroupId 1)].members) -join ',' | Should -Be (Get-TestUserId 1)
        $status = @($result.Cosmos.state | Where-Object { $_['type'] -eq 'status' })[0]
        $status['skipped'] | Should -Be 1
    }
}

Describe 'Renew-SignInCertificate (built)' {
    It 'adds the renewed certificate as the maintenance identity' {
        $current = Get-SignInCertificate -FromDays -300 -ToDays 40 -Name 'rdg-current'
        $renewed = Get-SignInCertificate -FromDays -1 -ToDays 365 -Name 'rdg-renewed'
        $state = @{
            Variables    = @{
                DG_MaintenanceClientId = $script:MaintenanceClient; DG_KeyVaultUri = 'https://rdg-contoso-kv.vault.azure.net'
                DG_SignInCertificateName = 'rdg-signin'; DG_SignInAppId = $script:AppId
            }
            KeyVault     = @{ 'rdg-signin' = $renewed.Base64 }
            Applications = @{
                $script:AppId = @{
                    id             = 'app-object-1'
                    keyCredentials = @(@{ keyId = 'k1'; type = 'AsymmetricX509Cert'; usage = 'Verify'; key = $current.Base64; displayName = $current.Name; startDateTime = $current.From; endDateTime = $current.To })
                }
            }
        }
        $result = Invoke-Runbook -Name 'Renew-SignInCertificate' -State $state
        $result.Error | Should -BeNullOrEmpty
        ($result.Output[0] | ConvertFrom-Json).Added | Should -Be $renewed.Thumbprint
        @($result.Applications[$script:AppId].keyCredentials) | Should -HaveCount 2
        $result.Calls | Should -Contain "Connect-MgGraph $script:MaintenanceClient"
        $result.Calls | Should -Contain "token https://vault.azure.net $script:MaintenanceClient"
    }

    It 'fails the job when the newest key expires within 21 days' {
        $current = Get-SignInCertificate -FromDays -300 -ToDays 10 -Name 'rdg-current'
        $state = @{
            Variables    = @{
                DG_MaintenanceClientId = $script:MaintenanceClient; DG_KeyVaultUri = 'https://rdg-contoso-kv.vault.azure.net'
                DG_SignInCertificateName = 'rdg-signin'; DG_SignInAppId = $script:AppId
            }
            KeyVault     = @{ 'rdg-signin' = $current.Base64 }
            Applications = @{
                $script:AppId = @{
                    id             = 'app-object-1'
                    keyCredentials = @(@{ keyId = 'k1'; type = 'AsymmetricX509Cert'; usage = 'Verify'; key = $current.Base64; displayName = $current.Name; startDateTime = $current.From; endDateTime = $current.To })
                }
            }
        }
        $result = Invoke-Runbook -Name 'Renew-SignInCertificate' -State $state
        $result.Error | Should -BeLike '*newest key*within 21 days*'
    }
}
