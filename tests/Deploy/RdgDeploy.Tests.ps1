#Requires -Version 7.4
# The deploy helpers: backend config, plan summary, web config, ARM calls, runbook publishing,
# smoke test. No Azure: calls go through fake -Invoke script blocks.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../deploy/RdgDeploy.psm1') -Force

    function Get-FakeArm {
        # Records calls; Handler gets one request (Method, Uri, Body, ContentType) and returns
        # StatusCode, Headers and Content.
        param([scriptblock] $Handler = { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{}' } })
        $state = [pscustomobject]@{ Calls = [System.Collections.Generic.List[object]]::new(); Handler = $Handler }
        $invoke = {
            param($Method, $Uri, $Body, $ContentType)
            $request = [pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body; ContentType = $ContentType }
            $state.Calls.Add($request)
            & $state.Handler $request
        }.GetNewClosure()
        [pscustomobject]@{ State = $state; Invoke = $invoke }
    }

    function Get-TestWebConfig {
        # A copy of the web app's staticwebapp.config.json in the temp folder.
        $path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "swa-$([guid]::NewGuid()).json"
        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../src/Web/public/staticwebapp.config.json') -Destination $path
        $path
    }

    function Get-TestAccountId {
        '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-rdg-prod/providers/Microsoft.Automation/automationAccounts/aa-rdg-prod'
    }

    function Get-TestPlanJson {
        param([object[]] $Change)
        @{ format_version = '1.2'; resource_changes = @($Change) } | ConvertTo-Json -Depth 10
    }

    function Get-TestRunbook {
        param([string] $Version = '1.2.0')
        "param()`n`$null = New-Module -Name DgEngine -ScriptBlock {`n    Set-StrictMode -Version Latest`n    `$script:DgEngineVersion = '$Version'`n}`n"
    }
}

Describe 'Get-RdgBackendConfig' {
    It 'points tofu init at the state container and the per-installation key' {
        $config = Get-RdgBackendConfig -ResourceGroup 'rg-rdg-prod-bootstrap' -StorageAccount 'strdgprodbs1a2b' -Environment 'prod'
        $config | Should -Contain '-backend-config=storage_account_name=strdgprodbs1a2b'
        $config | Should -Contain '-backend-config=container_name=tfstate'
        $config | Should -Contain '-backend-config=key=rdg-prod.tfstate'
    }
}

Describe 'Get-RdgPlanSummary' {
    It 'counts creates, updates, replaces and deletes and lists replaces and deletes first' {
        $json = Get-TestPlanJson -Change @(
            @{ address = 'module.app.azurerm_static_web_app.web'; change = @{ actions = @('update') } }
            @{ address = 'module.data.azurerm_cosmosdb_account.this'; change = @{ actions = @('delete', 'create') } }
            @{ address = 'module.engine.azurerm_automation_schedule.tick["05"]'; change = @{ actions = @('create') } }
            @{ address = 'module.engine.azurerm_automation_schedule.tick["10"]'; change = @{ actions = @('delete') } }
            @{ address = 'module.core.azurerm_key_vault.app'; change = @{ actions = @('no-op') } }
            @{ address = 'data.azurerm_client_config.current'; change = @{ actions = @('read') } }
        )
        $summary = Get-RdgPlanSummary -PlanJson $json
        $summary.Create | Should -Be 1
        $summary.Update | Should -Be 1
        $summary.Replace | Should -Be 1
        $summary.Delete | Should -Be 1
        $summary.Attention | Should -Be 2
        $summary.Markdown | Should -BeLike '*1 to create, 1 to update, 1 to replace, 1 to delete*'
        $replaceAt = $summary.Markdown.IndexOf('replace: `module.data.azurerm_cosmosdb_account.this`')
        ($replaceAt -ge 0 -and $replaceAt -lt $summary.Markdown.IndexOf('update: `module.app')) | Should -BeTrue
    }

    It 'says so when nothing changes' {
        $summary = Get-RdgPlanSummary -PlanJson (Get-TestPlanJson -Change @(@{ address = 'x'; change = @{ actions = @('no-op') } }))
        $summary.Attention | Should -Be 0
        $summary.Markdown | Should -BeLike '*No infrastructure changes.*'
    }

    It 'accepts a plan without resource_changes' {
        (Get-RdgPlanSummary -PlanJson '{"format_version":"1.2"}').Changes | Should -HaveCount 0
    }
}

Describe 'Set-RdgWebConfig' {
    It 'fills the tenant ID and the Key Vault of the sign-in certificate' {
        $path = Get-TestWebConfig
        Set-RdgWebConfig -Path $path -TenantId 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE' -KeyVaultName 'kv-rdg-prod-1a2b'
        $config = Get-Content -Raw -Path $path | ConvertFrom-Json
        $registration = $config.auth.identityProviders.azureActiveDirectory.registration
        $registration.openIdIssuer | Should -BeExactly 'https://login.microsoftonline.com/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/v2.0'
        $registration.clientSecretCertificateKeyVaultReference | Should -BeExactly '@Microsoft.KeyVault(SecretUri=https://kv-rdg-prod-1a2b.vault.azure.net/certificates/rdg-signin)'
        (Get-Content -Raw -Path $path) | Should -Not -BeLike '*__*__*'
    }

    It 'refuses a tenant ID that is not a GUID' {
        $path = Get-TestWebConfig
        { Set-RdgWebConfig -Path $path -TenantId 'contoso.onmicrosoft.com' -KeyVaultName 'kv-rdg-prod-1a2b' } | Should -Throw
    }

    It 'fails when an unknown placeholder is left' {
        $path = Get-TestWebConfig
        (Get-Content -Raw -Path $path).Replace('"cache-control": "no-store"', '"cache-control": "__CACHE__"') | Set-Content -Path $path -NoNewline
        { Set-RdgWebConfig -Path $path -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -KeyVaultName 'kv-rdg-prod-1a2b' } | Should -Throw -ExpectedMessage '*__CACHE__*'
    }
}

Describe 'Get-RdgRunbookVersion' {
    It 'reads the version stamp of a built runbook' {
        Get-RdgRunbookVersion -Content (Get-TestRunbook -Version '1.3.0-rc.2') | Should -BeExactly '1.3.0-rc.2'
    }

    It 'returns nothing for the placeholder OpenTofu creates' {
        Get-RdgRunbookVersion -Content "throw 'This runbook has not been deployed yet.'" | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-RdgArmRequest' {
    It 'parses JSON answers and fails with the ARM error on 4xx' {
        $fake = Get-FakeArm -Handler {
            param($Request)
            if ($Request.Method -eq 'GET') { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{"name":"x"}' } }
            else { [pscustomobject]@{ StatusCode = 403; Headers = @{}; Content = '{"error":{"code":"AuthorizationFailed","message":"no"}}' } }
        }
        (Invoke-RdgArmRequest -Method GET -Path '/subscriptions/s/x?api-version=1' -Invoke $fake.Invoke).Content.name | Should -BeExactly 'x'
        $fake.State.Calls[0].Uri | Should -BeExactly 'https://management.azure.com/subscriptions/s/x?api-version=1'
        { Invoke-RdgArmRequest -Method POST -Path '/subscriptions/s/y?api-version=1' -Invoke $fake.Invoke } | Should -Throw -ExpectedMessage '*HTTP 403*AuthorizationFailed*'
    }
}

Describe 'Publish-RdgRunbook' {
    It 'replaces the draft as text/powershell, waits for it, then publishes' {
        $fake = Get-FakeArm -Handler {
            param($Request)
            if ($Request.Uri -like '*/draft/content*') { [pscustomobject]@{ StatusCode = 202; Headers = @{ Location = @('https://management.azure.com/op/1') }; Content = '' } }
            elseif ($Request.Uri -like '*/op/1') { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '' } }
            else { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '' } }
        }
        $version = Publish-RdgRunbook -AutomationAccountId (Get-TestAccountId) -Name 'Sync-EntraGroups' -Content (Get-TestRunbook) -IntervalSeconds 0 -Invoke $fake.Invoke
        $version | Should -BeExactly '1.2.0'
        $calls = $fake.State.Calls
        $calls | Should -HaveCount 3
        $calls[0].Method | Should -BeExactly 'PUT'
        $calls[0].Uri | Should -BeLike '*/automationAccounts/aa-rdg-prod/runbooks/Sync-EntraGroups/draft/content?api-version=2024-10-23'
        $calls[0].ContentType | Should -BeExactly 'text/powershell'
        $calls[0].Body | Should -BeLike "*DgEngineVersion = '1.2.0'*"
        $calls[1].Uri | Should -BeExactly 'https://management.azure.com/op/1'
        $calls[2].Method | Should -BeExactly 'POST'
        $calls[2].Uri | Should -BeLike '*/runbooks/Sync-EntraGroups/publish?api-version=2024-10-23'
    }

    It 'refuses a file that is not a built runbook' {
        $fake = Get-FakeArm
        { Publish-RdgRunbook -AutomationAccountId (Get-TestAccountId) -Name 'x' -Content 'Write-Output 1' -Invoke $fake.Invoke } | Should -Throw -ExpectedMessage '*not a built runbook*'
        $fake.State.Calls | Should -HaveCount 0
    }

    It 'fails when the asynchronous operation fails' {
        $fake = Get-FakeArm -Handler {
            param($Request)
            if ($Request.Uri -like '*/draft/content*') { [pscustomobject]@{ StatusCode = 202; Headers = @{ 'Azure-AsyncOperation' = 'https://management.azure.com/op/2' }; Content = '' } }
            else { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{"status":"Failed"}' } }
        }
        { Publish-RdgRunbook -AutomationAccountId (Get-TestAccountId) -Name 'Sync-EntraGroups' -Content (Get-TestRunbook) -IntervalSeconds 0 -Invoke $fake.Invoke } | Should -Throw -ExpectedMessage '*Failed*'
    }
}

Describe 'Test-RdgDeployment' {
    It 'passes when health reports the version, anonymous calls are refused and runbooks carry the version' {
        $http = {
            param($Uri)
            if ($Uri -like '*/api/health') { [pscustomobject]@{ StatusCode = 200; Content = '{"status":"ok","version":"1.2.0"}' } }
            else { [pscustomobject]@{ StatusCode = 302; Content = '' } }
        }
        $content = { param($Name) "`$script:DgEngineVersion = '1.2.0' # $Name" }
        $results = @(Test-RdgDeployment -WebUrl 'https://x.azurestaticapps.net/' -Version '1.2.0' -Runbook @('Sync-EntraGroups') -RunbookContent $content -Http $http)
        $results | Should -HaveCount 3
        @($results | Where-Object { -not $_.Passed }) | Should -HaveCount 0
    }

    It 'fails on the old version and on an anonymous 200' {
        $http = {
            param($Uri)
            if ($Uri -like '*/api/health') { [pscustomobject]@{ StatusCode = 200; Content = '{"status":"ok","version":"1.1.0"}' } }
            else { [pscustomobject]@{ StatusCode = 200; Content = '[]' } }
        }
        $results = @(Test-RdgDeployment -WebUrl 'https://x.azurestaticapps.net' -Version '1.2.0' -Http $http)
        @($results | Where-Object { -not $_.Passed }) | Should -HaveCount 2
        $results[0].Detail | Should -BeLike "*version '1.1.0'*"
    }

    It 'fails when the API is not reachable yet' {
        $http = { [pscustomobject]@{ StatusCode = 404; Content = '<html>' } }
        $results = @(Test-RdgDeployment -WebUrl 'https://x.azurestaticapps.net' -Version '1.2.0' -Http $http)
        $results[0].Passed | Should -BeFalse
    }
}

Describe 'Get-RdgEncryptionSetting' {
    It 'reads the state Key Vault and key from the settings file' {
        $text = "environment = `"eval`"`nstate_key_vault_name  = `"kv-rdg-eval-bs1a2b`"`nstate_key_name = `"other-key`"`n"
        $values = Get-RdgEncryptionSetting -SettingsText $text
        $values.state_key_vault_name | Should -BeExactly 'kv-rdg-eval-bs1a2b'
        $values.state_key_name | Should -BeExactly 'other-key'
    }

    It 'defaults the key name and refuses an empty vault name' {
        (Get-RdgEncryptionSetting -SettingsText 'state_key_vault_name = "kv-x-bs1"').state_key_name | Should -BeExactly 'rdg-state'
        { Get-RdgEncryptionSetting -SettingsText 'state_key_vault_name = ""' } | Should -Throw -ExpectedMessage '*stage 1 prints it*'
    }
}

Describe 'Get-RdgAlertReceiverStatus' {
    It 'lists every email receiver and marks unconfirmed ones' {
        $group = @{ properties = @{ emailReceivers = @(
                    @{ name = 'email-0'; emailAddress = 'ops@contoso.org'; status = 'Enabled' }
                    @{ name = 'email-1'; emailAddress = 'new@contoso.org'; status = 'NotSpecified' }
                ) } }
        $receivers = @(Get-RdgAlertReceiverStatus -ActionGroup $group)
        $receivers | Should -HaveCount 2
        $receivers[0].Confirmed | Should -BeTrue
        $receivers[1].Email | Should -Be 'new@contoso.org'
        $receivers[1].Confirmed | Should -BeFalse
    }

    It 'returns nothing for an action group without email receivers' {
        @(Get-RdgAlertReceiverStatus -ActionGroup @{ properties = @{} }) | Should -HaveCount 0
    }
}
