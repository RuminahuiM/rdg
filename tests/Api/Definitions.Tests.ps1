#Requires -Version 7.4
# Definitions: list, create, read, update, delete. Every response is checked against openapi.yaml.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'ApiTestKit.ps1')
    function Get-SalesWorld {
        $world = Get-ApiWorld -Users @((Get-TestUser 1), (Get-TestUser 2))
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 1) -DisplayName 'Sales'
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 2) -DisplayName 'Finance'
        $world
    }
}

Describe 'POST /api/definitions' {
    It 'creates a definition with its audit record in one batch and answers 201 with ETag and Location' {
        $world = Get-SalesWorld
        $response = Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput -Change @{ frequencyMinutes = 60 })
        $response.StatusCode | Should -Be 201
        $response.Body.id | Should -BeLike 'def-*'
        $response.Headers['ETag'] | Should -Be $response.Body.etag
        $response.Headers['Location'] | Should -Be "/api/definitions/$($response.Body.id)"
        $response.Body.frequencyMinutes | Should -Be 60
        $response.Body.enabled | Should -BeTrue
        $response.Body.status | Should -BeNullOrEmpty
        $response.Body.createdBy | Should -Be 'admin@contoso.org'
        $audit = Get-StoredDocument -Store $world.Store -Container config -Type audit
        $audit | Should -HaveCount 1
        $audit[0]['action'] | Should -Be 'create'
        $audit[0]['pk'] | Should -Be $response.Body.id
        $audit[0]['ttl'] | Should -Be (60 * 86400)
        Test-StoredDocumentSchema -Store $world.Store | Should -HaveCount 0
    }

    It 'refuses readers' {
        $null = Get-SalesWorld
        (Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput) -Roles reader).StatusCode | Should -Be 403
    }

    It 'refuses a body that breaks the contract and names the field' {
        $null = Get-SalesWorld
        $body = Get-DefinitionInput -Change @{ colour = 'blue' }
        $response = Invoke-Api -Method POST -Route 'definitions' -Body $body
        $response.StatusCode | Should -Be 400
        $response.Body.errors[0].field | Should -Be 'colour'
        $response.Body.errors[0].message | Should -Be 'unknown field'
        (Invoke-Api -Method POST -Route 'definitions' -RawBody '{not json').StatusCode | Should -Be 400
        $low = Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput -Change @{ frequencyMinutes = 1 })
        $low.Body.errors[0].field | Should -Be 'frequencyMinutes'
    }

    It 'returns rule errors with their position' {
        $null = Get-SalesWorld
        $response = Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput -Rule 'user.departmnt -eq "Sales"')
        $response.StatusCode | Should -Be 400
        $response.Body.title | Should -Be 'Rule is not valid'
        $response.Body.errors[0].field | Should -Be 'rule'
        $response.Body.errors[0].position | Should -Be 0
        $response.Body.errors[0].message | Should -BeLike '*department*'
    }

    It 'checks the target group' {
        $world = Get-SalesWorld
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 3) -DisplayName 'Synced' -OnPremisesSynced $true
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 4) -DisplayName 'Team' -GroupTypes @('Unified')
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 5) -DisplayName 'Dynamic' -IsDynamic $true -GroupTypes @('DynamicMembership')
        $cases = @{
            (Get-TestGroupId 9) = "*doesn't exist*"
            (Get-TestGroupId 3) = '*on-premises AD*'
            (Get-TestGroupId 4) = '*Microsoft365 group, not Security*'
            (Get-TestGroupId 5) = '*adopt it*'
        }
        foreach ($groupId in $cases.Keys) {
            $response = Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput -GroupId $groupId)
            $response.StatusCode | Should -Be 400 -Because $groupId
            $response.Body.errors[0].message | Should -BeLike $cases[$groupId]
        }
    }

    It 'refuses a group another definition already manages with 409' {
        $null = Get-SalesWorld
        $null = Add-ApiDefinition -Body (Get-DefinitionInput)
        $response = Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput -Name 'Second')
        $response.StatusCode | Should -Be 409
        $response.Body.detail | Should -BeLike '*"Sales"*'
    }

    It 'starts an adoption and marks a dynamic group for conversion' {
        $world = Get-SalesWorld
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 5) -DisplayName 'Dynamic' -IsDynamic $true -GroupTypes @('DynamicMembership')
        $body = Get-DefinitionInput -GroupId (Get-TestGroupId 5) -Mode adopt
        $body.target.adopted = $true
        $created = Add-ApiDefinition -Body $body
        $created.target.adopted | Should -BeFalse
        $created.target.convertFromDynamic | Should -BeTrue
        (Get-StoredDocument -Store $world.Store -Container config -Type audit)[0]['action'] | Should -Be 'adopt'
    }

    It 'creates a group-to-be with target mode create and refuses a group ID there' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body @{ name = 'New'; groupType = 'Microsoft365'; target = @{ mode = 'create'; displayName = 'New team' }; rule = 'user.city -eq "Bern"' }
        $created.target.mode | Should -Be 'create'
        $bad = Invoke-Api -Method POST -Route 'definitions' -Body @{ name = 'New'; groupType = 'Security'; target = @{ mode = 'create'; displayName = 'X'; groupId = (Get-TestGroupId 1) }; rule = 'user.city -eq "Bern"' }
        $bad.StatusCode | Should -Be 400
        Test-StoredDocumentSchema -Store $world.Store | Should -HaveCount 0
    }

    It 'checks memberOf groups and the compare group' {
        $null = Get-SalesWorld
        $rule = "user.memberof -any (group.objectId -in ['$(Get-TestGroupId 77)'])"
        $response = Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput -Rule $rule)
        $response.StatusCode | Should -Be 400
        $response.Body.errors[0].message | Should -BeLike "*$(Get-TestGroupId 77)*doesn't exist*"
        $compare = Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput -Change @{ compareGroupId = (Get-TestGroupId 88) })
        $compare.Body.errors[0].field | Should -Be 'compareGroupId'
        $ok = Invoke-Api -Method POST -Route 'definitions' -Body (Get-DefinitionInput -Rule "user.memberof -any (group.objectId -in ['$(Get-TestGroupId 2)'])")
        $ok.StatusCode | Should -Be 201
    }
}

Describe 'GET /api/definitions and /api/definitions/{id}' {
    It 'lists with status, filters and pages of 50' {
        $world = Get-SalesWorld
        for ($i = 1; $i -le 55; $i++) {
            Write-StoredDocument -Store $world.Store -Container config -Document (Get-TestDefinition -Number $i -Change @{ name = ('Def {0:d2}' -f $i); enabled = ($i % 2 -eq 0) })
        }
        Write-StoredDocument -Store $world.Store -Container state -Document (Get-TestStatus -Number 3 -Change @{ lastResult = 'Blocked' })
        $first = Invoke-Api -Route 'definitions' -Roles reader
        $first.StatusCode | Should -Be 200
        $first.Body.items | Should -HaveCount 50
        $first.Body.items[0].name | Should -Be 'Def 01'
        $first.Body.continuationToken | Should -Not -BeNullOrEmpty
        $second = Invoke-Api -Route 'definitions' -Query @{ continuationToken = $first.Body.continuationToken }
        $second.Body.items | Should -HaveCount 5
        $second.Body.continuationToken | Should -BeNullOrEmpty
        (Invoke-Api -Route 'definitions' -Query @{ result = 'Blocked' }).Body.items[0].name | Should -Be 'Def 03'
        (Invoke-Api -Route 'definitions' -Query @{ enabled = 'true' }).Body.items | Should -HaveCount 27
        (Invoke-Api -Route 'definitions' -Query @{ search = 'def 1' }).Body.items | Should -HaveCount 10
        (Invoke-Api -Route 'definitions' -Query @{ groupType = 'Fancy' }).StatusCode | Should -Be 400
        (Invoke-Api -Route 'definitions' -Query @{ continuationToken = 'garbage' }).StatusCode | Should -Be 400
    }

    It 'returns one definition with its status and ETag, or 404' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        Write-StoredDocument -Store $world.Store -Container state -Document ([ordered]@{
                id = "status-$($created.id)"; pk = $created.id; type = 'status'; schemaVersion = 1; groupId = (Get-TestGroupId 1)
                lastSyncUtc = '2026-10-12T07:00:00.000Z'; lastResult = 'OK'; dryRunReason = $null; memberCount = 2; added = 2; removed = 0; skipped = 0
                excluded = @{ disabled = 1; guests = 0 }; warnings = @(); lastError = $null; lastRunId = $null; handledSyncRequestAt = $null
                pendingApproval = $null; usedApprovalHash = 'sha256:' + ('a' * 64); lastWrittenMembersHash = $null; compare = $null
            })
        $response = Invoke-Api -Route 'definitions/{id}' -Params @{ id = $created.id } -Roles reader
        $response.StatusCode | Should -Be 200
        $response.Body.status.memberCount | Should -Be 2
        $response.Body.status.ContainsKey('usedApprovalHash') | Should -BeFalse
        $response.Headers['ETag'] | Should -Be $response.Body.etag
        (Invoke-Api -Route 'definitions/{id}' -Params @{ id = 'def-01JA0000000000000000000099' }).StatusCode | Should -Be 404
        (Invoke-Api -Route 'definitions/{id}' -Params @{ id = 'nonsense' }).StatusCode | Should -Be 404
    }

    It 'adds the names of included, excluded and compare objects to one definition, not to the list' {
        $null = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput -Change @{
                includeUserIds = @(Get-TestUserId 1); excludeUserIds = @((Get-TestUserId 2), (Get-TestUserId 77)); compareGroupId = (Get-TestGroupId 2)
            })
        $response = Invoke-Api -Route 'definitions/{id}' -Params @{ id = $created.id } -Roles reader
        $response.StatusCode | Should -Be 200
        $response.Body.includeUsers[0].upn | Should -Be 'user1@contoso.org'
        $response.Body.includeUsers[0].displayName | Should -Be 'User 1'
        @($response.Body.excludeUsers).Count | Should -Be 1
        $response.Body.compareGroup.displayName | Should -Be 'Finance'
        $list = Invoke-Api -Route 'definitions'
        $list.Body.items[0].ContainsKey('includeUsers') | Should -BeFalse
    }

    It 'still answers when the names cannot be read' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput -Change @{ includeUserIds = @(Get-TestUserId 1) })
        $world.Tenant.Throttle = $true
        $response = Invoke-Api -Route 'definitions/{id}' -Params @{ id = $created.id } -WarningAction SilentlyContinue
        $response.StatusCode | Should -Be 200
        $response.Body.ContainsKey('includeUsers') | Should -BeFalse
        $response.Body.includeUserIds | Should -Be (Get-TestUserId 1)
    }
}

Describe 'PUT /api/definitions/{id}' {
    It 'needs If-Match, refuses an outdated one with who changed it, and audits the changed fields' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $update = Get-DefinitionInput -Rule 'user.department -eq "Finance"' -Change @{ dryRun = $true }
        (Invoke-Api -Method PUT -Route 'definitions/{id}' -Params @{ id = $created.id } -Body $update).StatusCode | Should -Be 428

        $stale = Invoke-Api -Method PUT -Route 'definitions/{id}' -Params @{ id = $created.id } -Body $update -IfMatch '"stale"'
        $stale.StatusCode | Should -Be 412
        $stale.Body.current.updatedBy | Should -Be 'admin@contoso.org'
        $stale.Body.current.etag | Should -Be $created.etag

        $world.Clock = [DateTimeOffset]'2026-10-12T09:00:00Z'
        $ok = Invoke-Api -Method PUT -Route 'definitions/{id}' -Params @{ id = $created.id } -Body $update -IfMatch $created.etag -Upn 'sam@contoso.org'
        $ok.StatusCode | Should -Be 200
        $ok.Body.rule | Should -Be 'user.department -eq "Finance"'
        $ok.Body.updatedBy | Should -Be 'sam@contoso.org'
        $ok.Body.updatedAt | Should -Be '2026-10-12T09:00:00.000Z'
        $ok.Body.createdAt | Should -Be '2026-10-12T08:00:00.000Z'
        $ok.Headers['ETag'] | Should -Not -Be $created.etag
        $audit = (Get-StoredDocument -Store $world.Store -Container config -Type audit).Where({ $_['action'] -eq 'update' })
        ($audit[0]['changes'] | ForEach-Object { $_['field'] }) -join ',' | Should -Be 'rule,dryRun'
        Test-StoredDocumentSchema -Store $world.Store | Should -HaveCount 0
    }

    It 'writes nothing when nothing changed' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $same = Invoke-Api -Method PUT -Route 'definitions/{id}' -Params @{ id = $created.id } -Body (Get-DefinitionInput) -IfMatch $created.etag
        $same.StatusCode | Should -Be 200
        $same.Body.etag | Should -Be $created.etag
        Get-StoredDocument -Store $world.Store -Container config -Type audit | Should -HaveCount 1
    }

    It 'keeps engine-owned fields and an approved adoption of the same group' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput -Mode adopt)
        $stored = (Get-StoredDocument -Store $world.Store -Container config -Type definition)[0]
        $stored['target']['adopted'] = $true
        $stored['syncRequest'] = [ordered]@{ at = '2026-10-12T07:59:00Z'; by = 'admin@contoso.org' }
        Write-StoredDocument -Store $world.Store -Container config -Document $stored
        $etag = (Invoke-Api -Route 'definitions/{id}' -Params @{ id = $created.id }).Body.etag
        $updated = Invoke-Api -Method PUT -Route 'definitions/{id}' -Params @{ id = $created.id } -Body (Get-DefinitionInput -Mode adopt -Name 'Renamed') -IfMatch $etag
        $updated.Body.target.adopted | Should -BeTrue
        $updated.Body.syncRequest.by | Should -Be 'admin@contoso.org'
    }
}

Describe 'DELETE /api/definitions/{id}' {
    It 'refuses while other rules reference the group, unless forced, and keeps the audit history' {
        $world = Get-SalesWorld
        $sales = Add-ApiDefinition -Body (Get-DefinitionInput)
        $null = Add-ApiDefinition -Body (Get-DefinitionInput -Name 'Uses sales' -GroupId (Get-TestGroupId 2) -Rule "user.memberof -any (group.objectId -in ['$(Get-TestGroupId 1)'])")
        Write-StoredDocument -Store $world.Store -Container state -Document (Get-TestStatus -Number 1 -Change @{ pk = $sales.id; id = "status-$($sales.id)" })

        (Invoke-Api -Method DELETE -Route 'definitions/{id}' -Params @{ id = $sales.id }).StatusCode | Should -Be 428
        $refused = Invoke-Api -Method DELETE -Route 'definitions/{id}' -Params @{ id = $sales.id } -IfMatch $sales.etag
        $refused.StatusCode | Should -Be 409
        $refused.Body.referencedBy[0].name | Should -Be 'Uses sales'

        $deleted = Invoke-Api -Method DELETE -Route 'definitions/{id}' -Params @{ id = $sales.id } -Query @{ force = 'true' } -IfMatch $sales.etag
        $deleted.StatusCode | Should -Be 204
        $deleted.Raw | Should -BeNullOrEmpty
        (Invoke-Api -Route 'definitions/{id}' -Params @{ id = $sales.id }).StatusCode | Should -Be 404
        (Get-StoredDocument -Store $world.Store -Container config -Type audit).Where({ $_['pk'] -eq $sales.id }) | Should -HaveCount 2
        (Get-StoredDocument -Store $world.Store -Container state -Type status).Where({ $_['pk'] -eq $sales.id }) | Should -HaveCount 0
        Test-StoredDocumentSchema -Store $world.Store | Should -HaveCount 0
    }
}

Describe 'Contract' {
    It 'every response matched openapi.yaml' {
        $script:ContractFailures | ForEach-Object { Write-Warning $_ }
        $script:ContractFailures | Should -HaveCount 0
    }
}
