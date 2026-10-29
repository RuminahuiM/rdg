#Requires -Version 7.4
# Sync now, approvals, runs, rule validation and preview. Every response is checked against openapi.yaml.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'ApiTestKit.ps1')
    function Get-SalesWorld {
        param([string] $AccessMode = 'read-write')
        $users = @((Get-TestUser 1), (Get-TestUser 2), (Get-TestUser 3 -Enabled $false), (Get-TestUser 4 -Department 'Finance'))
        $world = Get-ApiWorld -Users $users -AccessMode $AccessMode
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 1) -DisplayName 'Sales' -Members @((Get-TestUserId 1), (Get-TestUserId 4))
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 2) -DisplayName 'Finance'
        $world
    }
    # Puts a status with a pending approval next to a definition, as the engine would.
    function Write-PendingApproval {
        param($World, [string] $Id, [string] $Kind = 'changeLimit')
        Write-StoredDocument -Store $World.Store -Container state -Document ([ordered]@{
                id = "status-$Id"; pk = $Id; type = 'status'; schemaVersion = 1; groupId = (Get-TestGroupId 1)
                lastSyncUtc = '2026-10-12T07:00:00.000Z'; lastResult = 'Blocked'; dryRunReason = $null; memberCount = 2; added = 0; removed = 0; skipped = 0
                excluded = @{ disabled = 0; guests = 0 }; warnings = @(); lastError = 'over the limit'; lastRunId = $null; handledSyncRequestAt = $null
                pendingApproval = @{ kind = $Kind; diffHash = ('sha256:' + ('b' * 64)); adds = 40; removes = 1; percent = 205.0; detectedAt = '2026-10-12T07:00:00.000Z' }
                usedApprovalHash = $null; lastWrittenMembersHash = $null; compare = $null
            })
    }
}

Describe 'POST /api/definitions/{id}/sync' {
    It 'records the request with audit and starts a SyncNow job of the matching runbook' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $response = Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = $created.id }
        $response.StatusCode | Should -Be 202
        $response.Body.jobStarted | Should -BeTrue
        $response.Body.jobId | Should -Be '00000000-0000-4000-8000-0000000000b1'
        $world.Jobs[0].Runbook | Should -Be 'Sync-EntraGroups'
        $world.Jobs[0].Parameters.Mode | Should -Be 'SyncNow'
        $world.Jobs[0].Parameters.DefinitionId | Should -Be $created.id
        (Invoke-Api -Route 'definitions/{id}' -Params @{ id = $created.id }).Body.syncRequest.by | Should -Be 'admin@contoso.org'
        (Get-StoredDocument -Store $world.Store -Container config -Type audit).Where({ $_['action'] -eq 'syncNow' }) | Should -HaveCount 1
        Test-StoredDocumentSchema -Store $world.Store | Should -HaveCount 0
    }

    It 'returns the open request instead of starting another job within a minute' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $null = Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = $created.id }
        $world.Clock = $world.Clock.AddSeconds(30)
        $again = Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = $created.id }
        $again.StatusCode | Should -Be 202
        $again.Body.existingRequest | Should -BeTrue
        $world.Jobs | Should -HaveCount 1
        $world.Clock = $world.Clock.AddSeconds(60)
        (Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = $created.id }).Body.jobStarted | Should -BeTrue
        $world.Jobs | Should -HaveCount 2
    }

    It 'keeps the request when the job can''t start' {
        $world = Get-SalesWorld
        $world.FailJobs = $true
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $response = Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = $created.id }
        $response.StatusCode | Should -Be 202
        $response.Body.jobStarted | Should -BeFalse
        $response.Body.message | Should -BeLike '*next scheduled run*'
    }

    It 'refuses to sync a group RDG would create when read-only, and readers, and unknown definitions' {
        $null = Get-SalesWorld -AccessMode 'read-only'
        $created = Add-ApiDefinition -Body @{ name = 'New'; groupType = 'Security'; target = @{ mode = 'create'; displayName = 'New' }; rule = 'user.city -eq "Bern"' }
        (Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = $created.id }).StatusCode | Should -Be 409
        (Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = $created.id } -Roles reader).StatusCode | Should -Be 403
        (Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = 'def-01JA0000000000000000000099' }).StatusCode | Should -Be 404
    }

    It 'starts the Exchange runbook for mail group types' {
        $world = Get-SalesWorld
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 6) -DisplayName 'List' -Kind 'Distribution'
        $created = Add-ApiDefinition -Body @{ name = 'List'; groupType = 'Distribution'; target = @{ mode = 'existing'; groupId = (Get-TestGroupId 6) }; rule = 'user.city -eq "Bern"' }
        $null = Invoke-Api -Method POST -Route 'definitions/{id}/sync' -Params @{ id = $created.id }
        $world.Jobs[0].Runbook | Should -Be 'Sync-ExchangeGroups'
    }
}

Describe 'POST /api/definitions/{id}/approve' {
    It 'approves exactly the pending diff and audits it' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        (Invoke-Api -Method POST -Route 'definitions/{id}/approve' -Params @{ id = $created.id } -Body @{ kind = 'changeLimit'; diffHash = ('sha256:' + ('b' * 64)) }).StatusCode | Should -Be 409
        Write-PendingApproval -World $world -Id $created.id
        (Invoke-Api -Method POST -Route 'definitions/{id}/approve' -Params @{ id = $created.id } -Body @{ kind = 'changeLimit'; diffHash = ('sha256:' + ('c' * 64)) }).StatusCode | Should -Be 409
        (Invoke-Api -Method POST -Route 'definitions/{id}/approve' -Params @{ id = $created.id } -Body @{ kind = 'adopt'; diffHash = ('sha256:' + ('b' * 64)) }).StatusCode | Should -Be 409
        (Invoke-Api -Method POST -Route 'definitions/{id}/approve' -Params @{ id = $created.id } -Body @{ kind = 'changeLimit' }).StatusCode | Should -Be 400

        $approved = Invoke-Api -Method POST -Route 'definitions/{id}/approve' -Params @{ id = $created.id } -Body @{ kind = 'changeLimit'; diffHash = ('sha256:' + ('b' * 64)) }
        $approved.StatusCode | Should -Be 200
        $approved.Body.approval.adds | Should -Be 40
        $approved.Body.approval.by | Should -Be 'admin@contoso.org'
        $approved.Headers['ETag'] | Should -Be $approved.Body.etag
        (Get-StoredDocument -Store $world.Store -Container config -Type audit).Where({ $_['action'] -eq 'approve' }) | Should -HaveCount 1
        Test-StoredDocumentSchema -Store $world.Store | Should -HaveCount 0
    }

    It 'marks an adoption as adopted' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput -Mode adopt)
        Write-PendingApproval -World $world -Id $created.id -Kind adopt
        $approved = Invoke-Api -Method POST -Route 'definitions/{id}/approve' -Params @{ id = $created.id } -Body @{ kind = 'adopt'; diffHash = ('sha256:' + ('b' * 64)) }
        $approved.Body.target.adopted | Should -BeTrue
    }

    It 'refuses approvals in a read-only installation' {
        $world = Get-SalesWorld -AccessMode 'read-only'
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        Write-PendingApproval -World $world -Id $created.id
        (Invoke-Api -Method POST -Route 'definitions/{id}/approve' -Params @{ id = $created.id } -Body @{ kind = 'changeLimit'; diffHash = ('sha256:' + ('b' * 64)) }).StatusCode | Should -Be 409
    }
}

Describe 'GET /api/runs and /api/definitions/{id}/runs' {
    It 'lists runs newest first with a job link, filtered' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $base = (Get-StoredDocument -Store $world.Store -Container runs -Type run)
        $runs = @(
            @{ id = "run-00000000-0000-4000-8000-000000000001-$($created.id)"; pk = $created.id; startedAt = '2026-10-12T07:00:00.000Z'; result = 'OK' }
            @{ id = "run-00000000-0000-4000-8000-000000000002-$($created.id)"; pk = $created.id; startedAt = '2026-10-12T07:30:00.000Z'; result = 'Blocked' }
        )
        foreach ($run in $runs) {
            Write-StoredDocument -Store $world.Store -Container runs -Document ([ordered]@{
                    id = $run.id; pk = $run.pk; type = 'run'; schemaVersion = 1; jobId = ($run.id.Substring(4, 36)); runbook = 'Entra'; mode = 'Scheduled'
                    startedAt = $run.startedAt; durationMs = 120; engineVersion = '0.1.0'; definitionName = 'Sales'; groupId = (Get-TestGroupId 1)
                    result = $run.result; dryRun = $false; dryRunReason = $null; addedCount = 1; removedCount = 0; skippedCount = 0
                    added = @(@{ id = (Get-TestUserId 2); upn = 'user2@contoso.org' }); removed = @(); skipped = @(); excluded = @{ disabled = 0; guests = 0 }
                    manualChangesReverted = @{ added = 0; removed = 0 }; approval = $null; warnings = @(); error = $null; compare = $null
                })
        }
        Write-StoredDocument -Store $world.Store -Container runs -Document ([ordered]@{
                id = 'run-00000000-0000-4000-8000-000000000003-system'; pk = 'system'; type = 'run'; schemaVersion = 1; jobId = '00000000-0000-4000-8000-000000000003'
                runbook = 'Exchange'; mode = 'Scheduled'; startedAt = '2026-10-12T07:45:00.000Z'; durationMs = 5; result = 'Paused'; engineVersion = '0.1.0'; reason = 'paused'
            })
        $all = Invoke-Api -Route 'runs' -Roles reader
        $all.StatusCode | Should -Be 200
        ($all.Body.items | ForEach-Object { $_.result }) -join ',' | Should -Be 'Paused,Blocked,OK'
        $all.Body.items[0].definitionId | Should -BeNullOrEmpty
        $all.Body.items[1].jobUrl | Should -BeLike 'https://portal.azure.com/#resource/subscriptions/*/jobs/00000000-0000-4000-8000-000000000002'
        (Invoke-Api -Route 'runs' -Query @{ result = 'OK' }).Body.items | Should -HaveCount 1
        (Invoke-Api -Route 'runs' -Query @{ runbook = 'Exchange' }).Body.items | Should -HaveCount 1
        (Invoke-Api -Route 'runs' -Query @{ since = '2026-10-12T07:20:00Z' }).Body.items | Should -HaveCount 2
        (Invoke-Api -Route 'runs' -Query @{ since = 'yesterday' }).StatusCode | Should -Be 400
        $mine = Invoke-Api -Route 'definitions/{id}/runs' -Params @{ id = $created.id }
        $mine.Body.items | Should -HaveCount 2
        (Invoke-Api -Route 'definitions/{id}/runs' -Params @{ id = 'def-01JA0000000000000000000099' }).StatusCode | Should -Be 404
        $base | Should -HaveCount 0
    }
}

Describe 'POST /api/rules/validate' {
    It 'answers 200 with errors, positions and unknown groups' {
        $null = Get-SalesWorld
        $ok = Invoke-Api -Method POST -Route 'rules/validate' -Body @{ rule = "user.memberof -any (group.objectId -in ['$(Get-TestGroupId 1)'])" } -Roles reader
        $ok.StatusCode | Should -Be 200
        $ok.Body.valid | Should -BeTrue
        $ok.Body.referencedGroupIds | Should -Be (Get-TestGroupId 1)

        $bad = Invoke-Api -Method POST -Route 'rules/validate' -Body @{ rule = "user.department -eq`n" }
        $bad.Body.valid | Should -BeFalse
        $bad.Body.errors[0].line | Should -Be 2

        $unknown = Invoke-Api -Method POST -Route 'rules/validate' -Body @{ rule = "user.memberof -any (group.objectId -in ['$(Get-TestGroupId 55)'])" }
        $unknown.Body.valid | Should -BeFalse
        $unknown.Body.unknownGroupIds | Should -Be (Get-TestGroupId 55)
        $unknown.Body.errors[0].position | Should -Be 41

        (Invoke-Api -Method POST -Route 'rules/validate' -Body @{ text = 'x' }).StatusCode | Should -Be 400
    }
}

Describe 'POST /api/preview' {
    It 'previews a saved definition: members, excluded users, diff and change limit' {
        $null = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput -Change @{ excludeUserIds = @(Get-TestUserId 2) })
        $preview = Invoke-Api -Method POST -Route 'preview' -Body @{ definitionId = $created.id } -Roles reader
        $preview.StatusCode | Should -Be 200
        $preview.Body.memberCount | Should -Be 1
        $preview.Body.members[0].upn | Should -Be 'user1@contoso.org'
        ($preview.Body.excluded | ForEach-Object { "$($_.user.upn)=$($_.reason)" }) -join ',' | Should -Be 'user3@contoso.org=disabled,user2@contoso.org=excludeList'
        $preview.Body.diff.removes[0].upn | Should -Be 'user4@contoso.org'
        $preview.Body.diff.addCount | Should -Be 0
        $preview.Body.changeLimit.limitPercent | Should -Be 50
        $preview.Body.changeLimit.wouldBlock | Should -BeFalse
    }

    It 'previews an unsaved definition with a compare group and flags users without mail for Exchange types' {
        $world = Get-SalesWorld
        Add-TestGroup -Tenant $world.Tenant -Id (Get-TestGroupId 7) -DisplayName 'Old dynamic' -Members @((Get-TestUserId 1), (Get-TestUserId 4))
        $definition = @{ name = 'List'; groupType = 'Distribution'; target = @{ mode = 'create'; displayName = 'List' }; rule = 'user.department -eq "Sales"'; compareGroupId = (Get-TestGroupId 7) }
        $preview = Invoke-Api -Method POST -Route 'preview' -Body @{ definition = $definition }
        $preview.StatusCode | Should -Be 200
        $preview.Body.memberCount | Should -Be 0
        @($preview.Body.excluded | Where-Object { $_.reason -eq 'noExchangeRecipient' }) | Should -HaveCount 2
        $preview.Body.diff | Should -BeNullOrEmpty
        $preview.Body.compare.onlyInCompareCount | Should -Be 2
        $preview.Body.warnings[0] | Should -BeLike '*no mail address*'
    }

    It 'answers 400 for an invalid rule or an empty body, 404 for an unknown definition, 429 when Graph throttles' {
        $world = Get-SalesWorld
        (Invoke-Api -Method POST -Route 'preview' -Body @{ definition = @{ name = 'x'; groupType = 'Security'; target = @{ mode = 'create'; displayName = 'x' }; rule = 'user.city -eq' } }).StatusCode | Should -Be 400
        (Invoke-Api -Method POST -Route 'preview' -Body @{}).StatusCode | Should -Be 400
        (Invoke-Api -Method POST -Route 'preview' -Body @{ definitionId = 'def-01JA0000000000000000000099' }).StatusCode | Should -Be 404
        $both = @{ definitionId = 'def-01JA0000000000000000000099'; definition = @{ name = 'x'; groupType = 'Security'; target = @{ mode = 'create'; displayName = 'x' }; rule = 'user.city -eq "a"' } }
        (Invoke-Api -Method POST -Route 'preview' -Body $both).StatusCode | Should -Be 404
        $world.Tenant.Throttle = $true
        $throttled = Invoke-Api -Method POST -Route 'preview' -Body @{ definition = @{ name = 'x'; groupType = 'Security'; target = @{ mode = 'create'; displayName = 'x' }; rule = 'user.city -eq "a"' } }
        $throttled.StatusCode | Should -Be 429
        $throttled.Headers['Retry-After'] | Should -Be '7'
        $throttled.Body.retryAfterSeconds | Should -Be 7
    }

    It 'previews unsaved changes to a saved definition in place of the saved one' {
        $null = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        # Same group as the saved definition: without its ID the two would compete for the group.
        $edited = Get-DefinitionInput -Rule 'user.department -eq "Finance"'
        $preview = Invoke-Api -Method POST -Route 'preview' -Body @{ definitionId = $created.id; definition = $edited }
        $preview.StatusCode | Should -Be 200
        $preview.Body.memberCount | Should -Be 1
        $preview.Body.members[0].upn | Should -Be 'user4@contoso.org'
        $preview.Body.diff.removes[0].upn | Should -Be 'user1@contoso.org'
    }

    It 'counts every excluded user and flags a result that would empty the group' {
        $null = Get-SalesWorld
        $nobody = Get-DefinitionInput -Rule 'user.department -eq "Nobody"'
        $preview = Invoke-Api -Method POST -Route 'preview' -Body @{ definition = $nobody }
        $preview.StatusCode | Should -Be 200
        $preview.Body.emptyResult.wouldBlock | Should -BeTrue
        $preview.Body.emptyResult.currentMembers | Should -Be 2
        $nobody.allowEmpty = $true
        (Invoke-Api -Method POST -Route 'preview' -Body @{ definition = $nobody }).Body.emptyResult.wouldBlock | Should -BeFalse

        $sales = Invoke-Api -Method POST -Route 'preview' -Body @{ definition = (Get-DefinitionInput) }
        $sales.Body.excludedCounts.disabled | Should -Be 1
        $sales.Body.excludedCounts.guest | Should -Be 0
        $sales.Body.emptyResult.wouldBlock | Should -BeFalse
    }

    It 'reuses the user list for five minutes' {
        $world = Get-SalesWorld
        $created = Add-ApiDefinition -Body (Get-DefinitionInput)
        $null = Invoke-Api -Method POST -Route 'preview' -Body @{ definitionId = $created.id }
        $null = Invoke-Api -Method POST -Route 'preview' -Body @{ definitionId = $created.id }
        $world.Tenant.Calls.Where({ $_ -eq 'GetUsers' }) | Should -HaveCount 1
        $world.Clock = $world.Clock.AddMinutes(6)
        $null = Invoke-Api -Method POST -Route 'preview' -Body @{ definitionId = $created.id }
        $world.Tenant.Calls.Where({ $_ -eq 'GetUsers' }) | Should -HaveCount 2
    }
}

Describe 'Contract' {
    It 'every response matched openapi.yaml' {
        $script:ContractFailures | ForEach-Object { Write-Warning $_ }
        $script:ContractFailures | Should -HaveCount 0
    }
}
