#Requires -Version 7.4
# The bootstrap helpers: names (must match OpenTofu), settings file, permission sets, the
# pipeline's role condition, grant reconciliation, the sign-in app body and certificate keys.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../bootstrap/RdgBootstrap.psm1') -Force

    function Get-TestCertificate {
        param([string] $Subject = 'CN=RDG test', [int] $Days = 365)
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $Subject, $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $now = [DateTimeOffset]::UtcNow
        $certificate = $request.CreateSelfSigned($now.AddDays(-1), $now.AddDays($Days))
        [pscustomobject]@{
            Base64     = [System.Convert]::ToBase64String($certificate.RawData)
            Thumbprint = $certificate.Thumbprint
        }
    }

    function Get-FakeGraph {
        # Records calls; Handler gets one request (Method, Uri, Body) and returns the response.
        param([scriptblock] $Handler = { $null })
        $state = [pscustomobject]@{ Calls = [System.Collections.Generic.List[object]]::new(); Handler = $Handler }
        $invoke = {
            param($Method, $Uri, $Body)
            $request = [pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body }
            $state.Calls.Add($request)
            & $state.Handler $request
        }.GetNewClosure()
        [pscustomobject]@{ State = $state; Invoke = $invoke }
    }

    function Get-TestGraphResource {
        [pscustomobject]@{
            id          = 'graph-sp'
            displayName = 'Microsoft Graph'
            appRoles    = @(
                [pscustomobject]@{ id = 'r-user'; value = 'User.Read.All' }
                [pscustomobject]@{ id = 'r-member-read'; value = 'GroupMember.Read.All' }
                [pscustomobject]@{ id = 'r-member-write'; value = 'GroupMember.ReadWrite.All' }
            )
        }
    }

    function Get-TestScope {
        @{ 'User.Read' = 's-user'; openid = 's-openid'; profile = 's-profile'; email = 's-email' }
    }

    function Get-TestName {
        Get-RdgResourceName -NamePrefix rdg -Environment prod -SubscriptionId '11111111-2222-3333-4444-555555555555'
    }
}

Describe 'Get-RdgNameSuffix' {
    It 'matches OpenTofu substr(sha1(lower(id)), 0, 4)' {
        # Values computed with OpenTofu 1.12 (tofu apply of that expression).
        Get-RdgNameSuffix -SubscriptionId 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE' | Should -BeExactly 'e58c'
        Get-RdgNameSuffix -SubscriptionId '11111111-2222-3333-4444-555555555555' | Should -BeExactly '97d2'
    }
}

Describe 'Get-RdgResourceName' {
    It 'uses the names the OpenTofu modules create' {
        $names = Get-TestName
        $names.ResourceGroup | Should -BeExactly 'rg-rdg-prod'
        $names.AppKeyVault | Should -BeExactly 'kv-rdg-prod-97d2'
        $names.EngineIdentity | Should -BeExactly 'id-rdg-engine-prod'
        $names.MaintenanceIdentity | Should -BeExactly 'id-rdg-maintenance-prod'
        $names.StaticWebApp | Should -BeExactly 'stapp-rdg-prod'
        $names.FunctionsStorage | Should -BeExactly 'strdgprod97d2'
        $names.CosmosAccount | Should -BeExactly 'cosmos-rdg-prod-97d2'
        $names.SignInCertificate | Should -BeExactly 'rdg-signin'
    }

    It 'names the bootstrap resources of stage 1' {
        $names = Get-TestName
        $names.BootstrapGroup | Should -BeExactly 'rg-rdg-prod-bootstrap'
        $names.StateStorageAccount | Should -BeExactly 'strdgprodbs97d2'
        $names.StateKeyVault | Should -BeExactly 'kv-rdg-prod-bs97d2'
        $names.StateKey | Should -BeExactly 'rdg-prod.tfstate'
    }

    It 'keeps every Key Vault and storage name within the Azure limits at maximum length' {
        $long = Get-RdgResourceName -NamePrefix abcdef -Environment abcdefg -SubscriptionId '11111111-2222-3333-4444-555555555555'
        $long.StateKeyVault.Length | Should -Be 24
        $long.AppKeyVault.Length -le 24 | Should -BeTrue
        $long.StateStorageAccount.Length -le 24 | Should -BeTrue
        $long.FunctionsStorage.Length -le 24 | Should -BeTrue
        $long.StateStorageAccount | Should -BeLike 'st*'
    }

    It 'refuses an environment longer than 7 characters' {
        { Get-RdgResourceName -NamePrefix rdg -Environment staging1 -SubscriptionId '11111111-2222-3333-4444-555555555555' } | Should -Throw
    }
}

Describe 'Read-RdgSettingsFile' {
    It 'reads strings, numbers, booleans and lists, and skips comments and maps' {
        $path = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "rdg-$([guid]::NewGuid()).tfvars"
        @'
# comment
environment   = "test"   # trailing comment
tick_minutes  = 15
access_mode   = "read-write"
alert_emails  = ["a@contoso.org", "b@contoso.org"]
enabled       = true
tags = {
  "cost-center" = "IT"
  nested = { a = "b" }
}
signin_client_id = ""
'@ | Set-Content -LiteralPath $path
        try {
            $settings = Read-RdgSettingsFile -Path $path
        } finally {
            Remove-Item -LiteralPath $path
        }
        $settings.environment | Should -BeExactly 'test'
        $settings.tick_minutes | Should -Be 15
        $settings.access_mode | Should -BeExactly 'read-write'
        $settings.alert_emails | Should -HaveCount 2
        $settings.alert_emails[1] | Should -BeExactly 'b@contoso.org'
        $settings.enabled | Should -BeTrue
        $settings.signin_client_id | Should -BeExactly ''
        $settings.ContainsKey('tags') | Should -BeFalse
        $settings.ContainsKey('cost-center') | Should -BeFalse
        $settings.ContainsKey('nested') | Should -BeFalse
    }

    It 'reads the example settings file' {
        $settings = Read-RdgSettingsFile -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../examples/contoso.tfvars')
        $settings.tenant_domain | Should -BeExactly 'contoso.onmicrosoft.com'
        $settings.access_mode | Should -BeExactly 'read-only'
        $settings.alert_emails | Should -HaveCount 1
    }

    It 'fails for a missing file' {
        { Read-RdgSettingsFile -Path './no-such-file.tfvars' } | Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Get-RdgGraphPermission' {
    It 'gives a read-only engine read permissions only' {
        $engine = (Get-RdgGraphPermission -AccessMode read-only).engine
        $engine | Should -HaveCount 2
        $engine | Should -Contain 'User.Read.All'
        $engine | Should -Contain 'GroupMember.Read.All'
        $engine | Should -Not -Contain 'GroupMember.ReadWrite.All'
        $engine | Should -Not -Contain 'Group.Create'
    }

    It 'gives a read-write engine the four permissions of the matrix' {
        $engine = (Get-RdgGraphPermission -AccessMode read-write).engine
        $engine | Should -HaveCount 4
        foreach ($name in @('User.Read.All', 'GroupMember.ReadWrite.All', 'Group.Create', 'Group.ReadWrite.All')) { $engine | Should -Contain $name }
    }

    It 'keeps api and maintenance the same in both modes' {
        foreach ($mode in @('read-only', 'read-write')) {
            $set = Get-RdgGraphPermission -AccessMode $mode
            ($set.api -join ',') | Should -BeExactly 'User.Read.All,GroupMember.Read.All'
            ($set.maintenance -join ',') | Should -BeExactly 'Application.ReadWrite.OwnedBy'
        }
    }

    It 'lists every engine permission as managed, so switching mode can remove them' {
        (Get-RdgGraphPermission).engine | Should -HaveCount 5
    }

    It 'never grants directory-wide rights' {
        $all = (Get-RdgGraphPermission).Values | ForEach-Object { $_ }
        foreach ($name in @('Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All')) {
            $all | Should -Not -Contain $name
        }
    }
}

Describe 'Get-RdgExchangeRole' {
    It 'gives read-only installations View-Only Recipients only' {
        (Get-RdgExchangeRole -AccessMode read-only) -join ',' | Should -BeExactly 'View-Only Recipients'
    }

    It 'gives read-write installations the three roles of the design' {
        $roles = Get-RdgExchangeRole -AccessMode read-write
        $roles | Should -HaveCount 3
        $roles | Should -Contain 'Distribution Groups'
        $roles | Should -Contain 'Security Group Creation and Membership'
        $roles | Should -Not -Contain 'Organization Management'
    }
}

Describe 'Get-RdgRoleAssignmentCondition' {
    It 'limits writes and deletes to the given roles' {
        $condition = Get-RdgRoleAssignmentCondition -RoleDefinitionId @('DB79E9A7-68EE-4B58-9AEB-B90E7C24FCBA', '4fe576fe-1146-4730-92eb-48519fa6bf9f')
        $condition | Should -BeLike "*ActionMatches{'Microsoft.Authorization/roleAssignments/write'}*"
        $condition | Should -BeLike "*ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}*"
        $condition | Should -BeLike '*@Request`[Microsoft.Authorization/roleAssignments:RoleDefinitionId`] ForAnyOfAnyValues:GuidEquals {db79e9a7-68ee-4b58-9aeb-b90e7c24fcba, 4fe576fe-1146-4730-92eb-48519fa6bf9f}*'
        $condition | Should -BeLike '*@Resource`[Microsoft.Authorization/roleAssignments:RoleDefinitionId`]*'
    }

    It 'covers every role the OpenTofu modules assign, and not Owner or the RBAC roles' {
        $roles = Get-RdgPipelineRole
        $roles.Keys | Should -Contain 'Key Vault Certificate User'
        $roles.Keys | Should -Contain 'Automation Job Operator'
        $roles.Keys | Should -Contain 'Automation Runbook Operator'
        $roles.Keys | Should -Contain 'Storage Blob Data Owner'
        $roles.Keys | Should -Contain 'Storage Blob Data Contributor'
        $roles.Values | Should -Not -Contain '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'   # Owner
        $roles.Values | Should -Not -Contain 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'   # RBAC Administrator
        $roles.Values | Should -Not -Contain '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'   # User Access Administrator
    }

    It 'matches the role names the OpenTofu modules use' {
        $modules = Join-Path -Path $PSScriptRoot -ChildPath '../../infra/modules'
        $used = @(Get-ChildItem -Path $modules -Recurse -Filter '*.tf' | Select-String -Pattern 'role_definition_name\s*=\s*"([^"]+)"' |
                ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
        $used.Count -gt 0 | Should -BeTrue
        foreach ($name in $used) { (Get-RdgPipelineRole).Keys | Should -Contain $name }
    }

    It 'rejects anything that is not a GUID' {
        { Get-RdgRoleAssignmentCondition -RoleDefinitionId @('Owner') } | Should -Throw -ExpectedMessage '*not a role definition ID*'
    }
}

Describe 'Get-RdgAppRoleChange' {
    It 'adds what is missing and removes managed roles that are no longer wanted' {
        $current = @(
            [pscustomobject]@{ id = 'a1'; appRoleId = 'read' }
            [pscustomobject]@{ id = 'a2'; appRoleId = 'write' }
            [pscustomobject]@{ id = 'a3'; appRoleId = 'foreign' }
        )
        $change = Get-RdgAppRoleChange -Current $current -Desired @('read', 'create') -Managed @('read', 'write', 'create')
        $change.Add -join ',' | Should -BeExactly 'create'
        @($change.Remove).Count | Should -Be 1
        $change.Remove[0].id | Should -BeExactly 'a2'
    }

    It 'leaves grants someone else made alone' {
        $current = @([pscustomobject]@{ id = 'x'; appRoleId = 'foreign' })
        $change = Get-RdgAppRoleChange -Current $current -Desired @() -Managed @('read')
        @($change.Remove).Count | Should -Be 0
        @($change.Add).Count | Should -Be 0
    }
}

Describe 'Set-RdgAppRoleGrant' {
    It 'posts missing grants and deletes managed ones no longer wanted, on the right resource only' {
        $resource = Get-TestGraphResource
        $fake = Get-FakeGraph -Handler {
            param($Request)
            if ($Request.Method -eq 'GET') {
                [pscustomobject]@{ value = @(
                        [pscustomobject]@{ id = 'as-1'; appRoleId = 'r-member-write'; resourceId = 'graph-sp' }
                        [pscustomobject]@{ id = 'as-2'; appRoleId = 'r-member-write'; resourceId = 'other-api' }
                    )
                }
            }
        }
        $result = Set-RdgAppRoleGrant -PrincipalId 'engine-sp' -Resource $resource -Desired @('User.Read.All', 'GroupMember.Read.All') `
            -Managed @('User.Read.All', 'GroupMember.Read.All', 'GroupMember.ReadWrite.All') -Invoke $fake.Invoke
        $posts = @($fake.State.Calls | Where-Object Method -EQ 'POST')
        $deletes = @($fake.State.Calls | Where-Object Method -EQ 'DELETE')
        $posts | Should -HaveCount 2
        ($posts[0].Body | ConvertFrom-Json).appRoleId | Should -BeExactly 'r-user'
        ($posts[0].Body | ConvertFrom-Json).resourceId | Should -BeExactly 'graph-sp'
        $posts[0].Uri | Should -BeExactly 'https://graph.microsoft.com/v1.0/servicePrincipals/engine-sp/appRoleAssignments'
        $deletes | Should -HaveCount 1
        $deletes[0].Uri | Should -BeLike '*/appRoleAssignments/as-1'
        $result.Added -join ',' | Should -BeExactly 'User.Read.All,GroupMember.Read.All'
        $result.Removed -join ',' | Should -BeExactly 'GroupMember.ReadWrite.All'
    }

    It 'changes nothing under -WhatIf' {
        $resource = Get-TestGraphResource
        $fake = Get-FakeGraph -Handler { param($Request) if ($Request.Method -eq 'GET') { [pscustomobject]@{ value = @() } } }
        [void](Set-RdgAppRoleGrant -PrincipalId 'p' -Resource $resource -Desired @('User.Read.All') -Managed @('User.Read.All') -Invoke $fake.Invoke -WhatIf)
        @($fake.State.Calls | Where-Object Method -NE 'GET') | Should -HaveCount 0
    }

    It 'fails for a permission the API does not have' {
        $resource = Get-TestGraphResource
        $fake = Get-FakeGraph
        { Set-RdgAppRoleGrant -PrincipalId 'p' -Resource $resource -Desired @('Mail.Send') -Invoke $fake.Invoke } | Should -Throw -ExpectedMessage '*Mail.Send*'
    }

    It 'follows nextLink pages when reading assignments' {
        $resource = Get-TestGraphResource
        $fake = Get-FakeGraph -Handler {
            param($Request)
            if ($Request.Uri -like '*page2*') { [pscustomobject]@{ value = @([pscustomobject]@{ id = 'as-2'; appRoleId = 'r-member-read'; resourceId = 'graph-sp' }) } }
            elseif ($Request.Method -eq 'GET') {
                [pscustomobject]@{
                    value             = @([pscustomobject]@{ id = 'as-1'; appRoleId = 'r-user'; resourceId = 'graph-sp' })
                    '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/page2'
                }
            }
        }
        $result = Set-RdgAppRoleGrant -PrincipalId 'p' -Resource $resource -Desired @('User.Read.All', 'GroupMember.Read.All') -Invoke $fake.Invoke
        @($result.Added) | Should -HaveCount 0
        @($fake.State.Calls) | Should -HaveCount 2
    }
}

Describe 'Get-RdgSignInAppBody' {
    It 'describes a single-tenant app with Admin and Reader roles and delegated User.Read' {
        $scopes = Get-TestScope
        $body = Get-RdgSignInAppBody -DisplayName 'RDG sign-in (rdg-prod)' -RedirectUri 'https://x.azurestaticapps.net/.auth/login/aad/callback' -GraphScope $scopes
        $body.signInAudience | Should -BeExactly 'AzureADMyOrg'
        $body.appRoles.value -join ',' | Should -BeExactly 'Admin,Reader'
        $body.web.redirectUris[0] | Should -BeExactly 'https://x.azurestaticapps.net/.auth/login/aad/callback'
        $body.web.implicitGrantSettings.enableIdTokenIssuance | Should -BeTrue
        $access = $body.requiredResourceAccess[0]
        $access.resourceAppId | Should -BeExactly '00000003-0000-0000-c000-000000000000'
        @($access.resourceAccess | Where-Object { $_.type -ne 'Scope' }) | Should -HaveCount 0
        $access.resourceAccess.id | Should -Contain 's-user'
    }

    It 'keeps the IDs of existing app roles so assignments survive' {
        $scopes = Get-TestScope
        $existing = @([pscustomobject]@{ id = '11111111-0000-0000-0000-000000000001'; value = 'Admin' })
        $body = Get-RdgSignInAppBody -DisplayName 'x' -GraphScope $scopes -ExistingAppRole $existing
        ($body.appRoles | Where-Object { $_.value -eq 'Admin' }).id | Should -BeExactly '11111111-0000-0000-0000-000000000001'
        ($body.appRoles | Where-Object { $_.value -eq 'Reader' }).id | Should -Not -BeNullOrEmpty
    }

    It 'fails when a Graph scope is missing' {
        { Get-RdgSignInAppBody -DisplayName 'x' -GraphScope @{ 'User.Read' = 'a' } } | Should -Throw -ExpectedMessage '*openid*'
    }
}

Describe 'Get-RdgKeyCredentialPatch' {
    It 'adds a new certificate and keeps the current key' {
        $current = Get-TestCertificate -Subject 'CN=current'
        $next = Get-TestCertificate -Subject 'CN=next'
        $existing = @([pscustomobject]@{ keyId = 'k1'; type = 'AsymmetricX509Cert'; usage = 'Verify'; key = $current.Base64; displayName = 'CN=current'; endDateTime = [DateTimeOffset]::UtcNow.AddDays(30).ToString('o') })
        $patch = Get-RdgKeyCredentialPatch -Existing $existing -CertificateBase64 $next.Base64
        $patch.keyCredentials | Should -HaveCount 2
        $patch.keyCredentials[0].keyId | Should -BeExactly 'k1'
        $patch.keyCredentials[1].key | Should -BeExactly $next.Base64
        $patch.keyCredentials[1].usage | Should -BeExactly 'Verify'
    }

    It 'returns nothing when the certificate is already there' {
        $current = Get-TestCertificate -Subject 'CN=current'
        $existing = @([pscustomobject]@{ keyId = 'k1'; type = 'AsymmetricX509Cert'; usage = 'Verify'; key = $current.Base64; displayName = 'CN=current'; endDateTime = $null })
        Get-RdgKeyCredentialPatch -Existing $existing -CertificateBase64 $current.Base64 | Should -BeNullOrEmpty
    }

    It 'drops expired keys' {
        $current = Get-TestCertificate -Subject 'CN=current'
        $next = Get-TestCertificate -Subject 'CN=next'
        $existing = @([pscustomobject]@{ keyId = 'old'; type = 'AsymmetricX509Cert'; usage = 'Verify'; key = $current.Base64; displayName = 'CN=current'; endDateTime = [DateTimeOffset]::UtcNow.AddDays(-1).ToString('o') })
        $patch = Get-RdgKeyCredentialPatch -Existing $existing -CertificateBase64 $next.Base64
        $patch.keyCredentials | Should -HaveCount 1
        $patch.keyCredentials[0].displayName | Should -BeExactly 'CN=next'
    }

    It 'refuses keys read without their value' {
        $next = Get-TestCertificate -Subject 'CN=next'
        $existing = @([pscustomobject]@{ keyId = 'k1'; type = 'AsymmetricX509Cert'; usage = 'Verify'; key = $null; displayName = 'x'; endDateTime = $null })
        { Get-RdgKeyCredentialPatch -Existing $existing -CertificateBase64 $next.Base64 } | Should -Throw -ExpectedMessage '*without its value*'
    }
}

Describe 'Get-RdgTestUserData' {
    It 'creates the same invented users every time, every fifth disabled' {
        $users = @(Get-RdgTestUserData -Count 10 -Domain 'contoso.onmicrosoft.com')
        $users | Should -HaveCount 10
        $users[0].UserPrincipalName | Should -BeExactly 'rdgtest01@contoso.onmicrosoft.com'
        @($users | Where-Object { -not $_.AccountEnabled }) | Should -HaveCount 2
        $users[4].AccountEnabled | Should -BeFalse
        (@(Get-RdgTestUserData -Count 10 -Domain 'contoso.onmicrosoft.com'))[3].Department | Should -BeExactly $users[3].Department
    }

    It 'sets all 15 extension attributes, marking the user as test data' {
        $user = @(Get-RdgTestUserData -Count 2 -Domain 'contoso.onmicrosoft.com')[1]
        $user.ExtensionAttributes.Keys | Should -HaveCount 15
        $user.ExtensionAttributes.extensionAttribute15 | Should -BeExactly 'rdg-test'
        $user.ExtensionAttributes.extensionAttribute3 | Should -BeExactly 'Board'
    }
}

Describe 'Get-RdgUninstallPlan' {
    It 'removes the tenant side first, then the RDG resources, the state and the pipeline app' {
        $plan = Get-RdgUninstallPlan -Names (Get-TestName)
        $plan.Steps | Should -HaveCount 4
        $plan.Steps[0].Target | Should -BeExactly 'Tenant'
        $plan.Steps[1].Target | Should -BeExactly 'rg-rdg-prod'
        $plan.Steps[2].Target | Should -BeExactly 'rg-rdg-prod-bootstrap'
        $plan.Steps[3].Target | Should -BeExactly 'RDG pipeline (rdg-prod)'
        ($plan.Steps | ForEach-Object Step) -join ',' | Should -BeExactly '1,2,3,4'
    }

    It 'leaves out what the switches keep and says so' {
        $plan = Get-RdgUninstallPlan -Names (Get-TestName) -SkipTenant -KeepBootstrap -KeepPipelineApp
        $plan.Steps | Should -HaveCount 1
        $plan.Steps[0].Target | Should -BeExactly 'rg-rdg-prod'
        ($plan.Kept -join "`n") | Should -BeLike '*-SkipTenant*'
        ($plan.Kept -join "`n") | Should -BeLike '*-KeepBootstrap*'
        ($plan.Kept -join "`n") | Should -BeLike '*-KeepPipelineApp*'
    }

    It 'always lists the soft-deleted Key Vaults and the groups that stay' {
        $kept = (Get-RdgUninstallPlan -Names (Get-TestName)).Kept -join "`n"
        $kept | Should -BeLike '*kv-rdg-prod-97d2*kv-rdg-prod-bs97d2*90 days*'
        $kept | Should -BeLike "*'RDG Admins'*"
    }
}
