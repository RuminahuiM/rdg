#Requires -Version 7.4
# Settings, audit, directory pickers, session, roles source, errors, and the Functions layout.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'ApiTestKit.ps1')
    $script:ApiRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../src/Api'
    function Get-SettingsInput {
        param([hashtable] $Change = @{})
        $current = (Invoke-Api -Route 'settings').Body
        $body = @{}
        foreach ($key in @('paused', 'verboseLogging', 'changeLimitPercent', 'changeLimitMinChanges', 'newGroupsDryRun', 'nestedMembers', 'frequencyOptions', 'naming', 'marker', 'auditRetentionDays')) {
            $body[$key] = $current[$key]
        }
        foreach ($key in $Change.Keys) { $body[$key] = $Change[$key] }
        $body
    }
}

Describe 'Session and system' {
    It 'GET /api/health answers anonymously with the version only' {
        $null = Get-ApiWorld
        $health = Invoke-Api -Route 'health' -Anonymous
        $health.StatusCode | Should -Be 200
        $health.Body.status | Should -Be 'ok'
        $health.Body.version | Should -Be '0.1.0'
        $health.Body.Keys | Should -HaveCount 2
    }

    It 'GET /api/me returns the caller, roles and access mode; 401 without sign-in, 403 without a role' {
        $null = Get-ApiWorld -AccessMode 'read-only'
        $me = Invoke-Api -Route 'me' -Roles reader -Upn 'reader@contoso.org'
        $me.StatusCode | Should -Be 200
        $me.Body.upn | Should -Be 'reader@contoso.org'
        $me.Body.roles | Should -Be 'reader'
        $me.Body.accessMode | Should -Be 'read-only'
        $me.Headers['x-correlation-id'] | Should -Not -BeNullOrEmpty
        (Invoke-Api -Route 'me' -Anonymous).StatusCode | Should -Be 401
        (Invoke-Api -Route 'me' -Roles @()).StatusCode | Should -Be 403
    }

    It 'refuses an unreadable principal header with 401' {
        $null = Get-ApiWorld
        $response = Invoke-DgApiFunction -Route 'me' -Request @{ Method = 'GET'; Headers = @{ 'X-MS-CLIENT-PRINCIPAL' = 'not base64!' } } -InformationAction SilentlyContinue
        $response.StatusCode | Should -Be 401
    }

    It 'POST /api/roles maps the app roles claim' {
        $null = Get-ApiWorld
        $body = @{
            identityProvider = 'aad'; userId = 'u1'; userDetails = 'a@contoso.org'
            claims = @(@{ typ = 'roles'; val = 'Admin' }, @{ typ = 'roles'; val = 'Reader' }, @{ typ = 'roles'; val = 'Owner' }, @{ typ = 'name'; val = 'A' })
        }
        $roles = Invoke-Api -Method POST -Route 'roles' -Body $body -Anonymous
        $roles.StatusCode | Should -Be 200
        ($roles.Body.roles -join ',') | Should -Be 'admin,reader'
        (Invoke-Api -Method POST -Route 'roles' -Body @{ claims = @() } -Anonymous).Body.roles | Should -HaveCount 0
    }

    It 'answers 405 for a method the contract does not define' {
        $null = Get-ApiWorld
        $response = Invoke-DgApiFunction -Route 'me' -Request @{ Method = 'DELETE'; Headers = @{} }
        $response.StatusCode | Should -Be 405
    }

    It 'turns an unexpected failure into 500 with a correlation ID' {
        $world = Get-ApiWorld
        $world.Store.Containers.Remove('config')
        $response = Invoke-Api -Route 'settings'
        $response.StatusCode | Should -Be 500
        $response.Body.correlationId | Should -Be $response.Headers['x-correlation-id']
        $response.Body.detail | Should -Not -BeLike '*config*'
    }
}

Describe 'Settings on a new installation' {
    It 'creates the default settings document on first use' {
        $world = Get-ApiWorld
        $world.Store.Containers.config.Clear()
        $response = Invoke-Api -Route 'settings' -Roles reader
        $response.StatusCode | Should -Be 200
        $response.Body.newGroupsDryRun | Should -BeTrue
        $response.Body.paused | Should -BeFalse
        ($response.Body.frequencyOptions -join ',') | Should -Be '15,30,60,360,1440'
        $world.Store.Containers.config.Count | Should -Be 1
    }
}

Describe 'Settings' {
    It 'GET returns the settings with ETag; PUT needs If-Match, records the pause and audits the change' {
        $world = Get-ApiWorld
        $settings = Invoke-Api -Route 'settings' -Roles reader
        $settings.StatusCode | Should -Be 200
        $settings.Headers['ETag'] | Should -Be $settings.Body.etag
        $body = Get-SettingsInput -Change @{ paused = $true; changeLimitPercent = 40 }
        (Invoke-Api -Method PUT -Route 'settings' -Body $body).StatusCode | Should -Be 428
        (Invoke-Api -Method PUT -Route 'settings' -Body $body -IfMatch '"old"').StatusCode | Should -Be 412
        (Invoke-Api -Method PUT -Route 'settings' -Body $body -IfMatch $settings.Body.etag -Roles reader).StatusCode | Should -Be 403
        $updated = Invoke-Api -Method PUT -Route 'settings' -Body $body -IfMatch $settings.Body.etag -Upn 'boss@contoso.org'
        $updated.StatusCode | Should -Be 200
        $updated.Body.paused | Should -BeTrue
        $updated.Body.pausedBy | Should -Be 'boss@contoso.org'
        $updated.Body.pausedAt | Should -Be '2026-10-12T08:00:00.000Z'
        $updated.Body.changeLimitPercent | Should -Be 40
        $audit = (Get-StoredDocument -Store $world.Store -Container config -Type audit)
        $audit[0]['pk'] | Should -Be 'settings'
        ($audit[0]['changes'] | ForEach-Object { $_['field'] }) -join ',' | Should -Be 'paused,changeLimitPercent'

        $resumed = Invoke-Api -Method PUT -Route 'settings' -Body (Get-SettingsInput -Change @{ paused = $false }) -IfMatch $updated.Body.etag
        $resumed.Body.pausedBy | Should -BeNullOrEmpty
        Test-StoredDocumentSchema -Store $world.Store | Should -HaveCount 0
    }

    It 'refuses settings outside the contract' {
        $null = Get-ApiWorld
        $etag = (Invoke-Api -Route 'settings').Body.etag
        $bad = Invoke-Api -Method PUT -Route 'settings' -Body (Get-SettingsInput -Change @{ changeLimitPercent = 0 }) -IfMatch $etag
        $bad.StatusCode | Should -Be 400
        $bad.Body.errors[0].field | Should -Be 'changeLimitPercent'
    }
}

Describe 'GET /api/audit' {
    It 'lists changes newest first, filtered by definition, person and time' {
        $world = Get-ApiWorld
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 1) -DisplayName 'Sales'
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $world.Clock = $world.Clock.AddHours(1)
        $etag = (Invoke-Api -Route 'settings').Body.etag
        $null = Invoke-Api -Method PUT -Route 'settings' -Body (Get-SettingsInput -Change @{ verboseLogging = $true }) -IfMatch $etag -Upn 'sam@contoso.org'
        $all = Invoke-Api -Route 'audit' -Roles reader
        ($all.Body.items | ForEach-Object { $_.action }) -join ',' | Should -Be 'settings,create'
        $all.Body.items[0].definitionId | Should -BeNullOrEmpty
        $all.Body.items[1].definitionName | Should -Be 'Sales'
        (Invoke-Api -Route 'audit' -Query @{ definitionId = $created.id }).Body.items | Should -HaveCount 1
        (Invoke-Api -Route 'audit' -Query @{ by = 'SAM@contoso.org' }).Body.items | Should -HaveCount 1
        (Invoke-Api -Route 'audit' -Query @{ from = '2026-10-12T08:30:00Z' }).Body.items | Should -HaveCount 1
        (Invoke-Api -Route 'audit' -Query @{ to = '2026-10-12T08:30:00Z' }).Body.items | Should -HaveCount 1
        (Invoke-Api -Route 'audit' -Query @{ from = 'soon' }).StatusCode | Should -Be 400
        (Invoke-Api -Route 'audit' -Query @{ definitionId = 'x' }).StatusCode | Should -Be 400
    }
}

Describe 'Directory pickers' {
    It 'finds users by prefix' {
        $null = Get-ApiWorld -Users @((Get-TestUser 1), (Get-TestUser 2 -UserType 'Guest'))
        $users = Invoke-Api -Route 'directory/users' -Query @{ search = 'User' } -Roles reader
        $users.StatusCode | Should -Be 200
        $users.Body.items | Should -HaveCount 2
        $users.Body.items[1].userType | Should -Be 'Guest'
        (Invoke-Api -Route 'directory/users' -Query @{ search = 'U' }).StatusCode | Should -Be 400
        (Invoke-Api -Route 'directory/users').StatusCode | Should -Be 400
    }

    It 'finds groups with the flags the pickers need' {
        $world = Get-ApiWorld
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 1) -DisplayName 'Sales'
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 2) -DisplayName 'Sales dynamic' -IsDynamic $true -GroupTypes @('DynamicMembership') -MembershipRule 'user.department -eq "Sales"'
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 3) -DisplayName 'Sales list' -Kind 'Distribution'
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $groups = Invoke-Api -Route 'directory/groups' -Query @{ search = 'Sales' }
        $groups.StatusCode | Should -Be 200
        $groups.Body.items | Should -HaveCount 3
        $groups.Body.items[0].managedByDefinitionId | Should -Be $created.id
        $groups.Body.items[0].linkedToName | Should -Be 'Sales'
        $groups.Body.items[1].isDynamic | Should -BeTrue
        $groups.Body.items[1].membershipRule | Should -Be 'user.department -eq "Sales"'
        $groups.Body.items[2].groupType | Should -Be 'Distribution'
    }
}

Describe 'Functions layout' {
    It 'has one function per route, each route an OpenAPI path, and every operation reachable' {
        $operations = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($folder in Get-ChildItem -Path $script:ApiRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'function.json') }) {
            $binding = (Get-Content -Raw (Join-Path $folder.FullName 'function.json') | ConvertFrom-Json).bindings | Where-Object { $_.type -eq 'httpTrigger' }
            $binding.authLevel | Should -Be 'anonymous'
            $path = $script:OpenApi.paths['/' + $binding.route]
            $path | Should -Not -BeNullOrEmpty -Because $folder.Name
            foreach ($method in $binding.methods) {
                $path[$method] | Should -Not -BeNullOrEmpty -Because "$($folder.Name) $method"
                [void]$operations.Add($path[$method].operationId)
            }
            (Get-Content -Raw (Join-Path $folder.FullName 'run.ps1')) | Should -Be (Get-Content -Raw (Join-Path $script:ApiRoot 'me/run.ps1'))
        }
        $all = foreach ($route in $script:OpenApi.paths.Values) { foreach ($method in @('get', 'post', 'put', 'delete')) { if ($route[$method]) { $route[$method].operationId } } }
        $operations.Count | Should -Be @($all).Count
        $operations.Count | Should -Be 19
    }

    It 'has a handler for every operation' {
        foreach ($route in $script:OpenApi.paths.Values) {
            foreach ($method in @('get', 'post', 'put', 'delete')) {
                if (-not $route[$method]) { continue }
                $id = $route[$method].operationId
                $handler = 'Invoke-DgApi' + $id.Substring(0, 1).ToUpperInvariant() + $id.Substring(1)
                InModuleScope DgApi -Parameters @{ H = $handler } { [bool](Get-Command -Name $H -ErrorAction SilentlyContinue) } | Should -BeTrue -Because $handler
            }
        }
    }

    It 'keeps the route prefix "api" and managed dependencies off' {
        $hostJson = Get-Content -Raw (Join-Path $script:ApiRoot 'host.json') | ConvertFrom-Json
        $hostJson.extensions.http.routePrefix | Should -Be 'api'
        $hostJson.managedDependency.enabled | Should -BeFalse
    }
}

Describe 'Contract' {
    It 'every response matched openapi.yaml' {
        $script:ContractFailures | ForEach-Object { Write-Warning $_ }
        $script:ContractFailures | Should -HaveCount 0
    }
}
