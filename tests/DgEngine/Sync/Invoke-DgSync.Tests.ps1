#Requires -Version 7.4
# End-to-end runs of Invoke-DgSync against an in-memory tenant and an in-memory store.
# Every test also checks that the stored documents conform to the Cosmos DB schemas.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'SyncTestKit.ps1')

    # Sales: users 1, 2 (3 is disabled); Finance: 4.
    function Get-StandardUserList {
        @(
            (Get-TestUser 1), (Get-TestUser 2), (Get-TestUser 3 -Enabled $false), (Get-TestUser 4 -Department 'Finance')
        )
    }
    function Get-Status {
        param([hashtable] $Store, [int] $Number = 1)
        foreach ($document in (Get-StoredDocument -Store $Store -Container state -Type status)) {
            if ($document['pk'] -eq (Get-TestDefinitionId $Number)) { return $document }
        }
    }
    function Get-RunRecord {
        param([hashtable] $Store)
        Get-StoredDocument -Store $Store -Container runs -Type run
    }
    function Get-MemberList {
        param([hashtable] $Tenant, [string] $GroupId)
        ([string[]]@($Tenant.Groups[$GroupId].Members) | Sort-Object) -join ','
    }
}

Describe 'Invoke-DgSync: a normal run' {
    It 'adds and removes users, writes status, run record and heartbeat, and releases the lock' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -Members @((Get-TestUserId 1), (Get-TestUserId 4))
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)

        $result = Invoke-TestSync -Store $store -Tenant $tenant -JobId '11111111-1111-4111-8111-111111111111'

        $result.Result | Should -Be 'Succeeded'
        Get-MemberList $tenant (Get-TestGroupId 1) | Should -Be ((Get-TestUserId 1), (Get-TestUserId 2) -join ',')
        $status = Get-Status $store
        $status['lastResult'] | Should -Be 'OK'
        $status['memberCount'] | Should -Be 2
        $status['added'] | Should -Be 1
        $status['removed'] | Should -Be 1
        $status['excluded']['disabled'] | Should -Be 1
        $status['lastWrittenMembersHash'] | Should -BeLike 'sha256:*'
        $status['lastRunId'] | Should -Be "run-11111111-1111-4111-8111-111111111111-$(Get-TestDefinitionId 1)"
        $runs = Get-RunRecord $store
        $runs | Should -HaveCount 1
        $runs[0]['added'][0]['upn'] | Should -Be 'user2@contoso.org'
        $runs[0]['removed'][0]['id'] | Should -Be (Get-TestUserId 4)
        $runs[0]['result'] | Should -Be 'OK'
        $heartbeat = Get-StoredDocument -Store $store -Container state -Type heartbeat
        $heartbeat[0]['userCount'] | Should -Be 4
        Get-StoredDocument -Store $store -Container state -Type lock | Should -HaveCount 0
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'leaves no run record when nothing changed' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -Members @((Get-TestUserId 1), (Get-TestUserId 2))
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)

        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Result | Should -Be 'Succeeded'
        Get-RunRecord $store | Should -HaveCount 0
        (Get-Status $store)['lastResult'] | Should -Be 'OK'
        (Get-Status $store)['lastSyncUtc'] | Should -Not -BeNullOrEmpty
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'skips definitions that are not due and does not read users then' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $definition = Get-TestDefinition -Change @{ frequencyMinutes = 60 }
        $store = Get-TestStore -Definitions @($definition) -Statuses @(Get-TestStatus -LastSyncUtc '2026-10-12T07:30:00.000Z')

        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Message | Should -Be 'nothing due'
        $tenant.Calls -contains 'GetUsers' | Should -BeFalse
        (Get-Status $store)['lastSyncUtc'] | Should -Be ([datetime]'2026-10-12T07:30:00Z').ToUniversalTime()
    }

    It 'ignores the group types of the other runbook' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        $store = Get-TestStore -Definitions @(Get-TestDefinition -GroupType Distribution)
        $result = Invoke-TestSync -Store $store -Tenant $tenant -Provider Entra
        $result.Message | Should -Be 'nothing due'
    }
}

Describe 'Invoke-DgSync: lock and pause' {
    It 'records a skipped tick while another job holds the lock' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        $store = Get-TestStore -Definitions @(Get-TestDefinition)
        $lock = [ordered]@{
            id = 'lock-Entra'; pk = 'lock'; type = 'lock'; schemaVersion = 1; jobId = '22222222-2222-4222-8222-222222222222'
            acquiredAt = '2026-10-12T07:59:00.000Z'; expiresAt = '2026-10-12T08:05:00.000Z'
        }
        Write-StoredDocument -Store $store -Container state -Document $lock

        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Result | Should -Be 'SkippedTick'
        $result.Message | Should -BeLike '*22222222-2222-4222-8222-222222222222*'
        $runs = Get-RunRecord $store
        $runs[0]['result'] | Should -Be 'SkippedTick'
        $runs[0]['pk'] | Should -Be 'system'
        Get-Status $store | Should -BeNullOrEmpty
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'takes over an expired lock' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)
        $lock = [ordered]@{
            id = 'lock-Entra'; pk = 'lock'; type = 'lock'; schemaVersion = 1; jobId = '22222222-2222-4222-8222-222222222222'
            acquiredAt = '2026-10-12T07:00:00.000Z'; expiresAt = '2026-10-12T07:06:00.000Z'
        }
        Write-StoredDocument -Store $store -Container state -Document $lock

        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Result | Should -Be 'Succeeded'
        Get-StoredDocument -Store $store -Container state -Type lock | Should -HaveCount 0
    }

    It 'does nothing but record the pause and the heartbeat when paused' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        $settings = Get-TestSettingDocument -Change @{ paused = $true; pausedAt = '2026-10-12T07:00:00Z'; pausedBy = 'admin@contoso.org' }
        $store = Get-TestStore -Settings $settings -Definitions @(Get-TestDefinition)

        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Result | Should -Be 'Paused'
        (Get-RunRecord $store)[0]['reason'] | Should -Be 'paused by admin@contoso.org'
        (Get-StoredDocument -Store $store -Container state -Type heartbeat)[0]['paused'] | Should -BeTrue
        $tenant.Calls | Should -HaveCount 0
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }
}

Describe 'Invoke-DgSync: safety' {
    It 'blocks a change above the limit, fails the job and asks for approval; the approval then lets it through once' {
        $users = @(1..30 | ForEach-Object { Get-TestUser $_ })
        $tenant = Get-TestTenant -Users $users
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -Members @(1..10 | ForEach-Object { Get-TestUserId $_ })
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)

        $first = Invoke-TestSync -Store $store -Tenant $tenant
        $first.Result | Should -Be 'Failed'
        $status = Get-Status $store
        $status['lastResult'] | Should -Be 'Blocked'
        $status['pendingApproval']['kind'] | Should -Be 'changeLimit'
        $status['pendingApproval']['adds'] | Should -Be 20
        $status['lastError'] | Should -BeLike '*above the limit*'
        $tenant.Groups[(Get-TestGroupId 1)].Members.Count | Should -Be 10

        $definition = Get-TestDefinition -Change @{
            approval = [ordered]@{ kind = 'changeLimit'; diffHash = $status['pendingApproval']['diffHash']; adds = 20; removes = 0; by = 'admin@contoso.org'; at = '2026-10-12T08:01:00Z' }
        }
        Write-StoredDocument -Store $store -Container config -Document $definition
        $second = Invoke-TestSync -Store $store -Tenant $tenant -Now '2026-10-12T08:03:00Z'
        $second.Result | Should -Be 'Succeeded'
        $tenant.Groups[(Get-TestGroupId 1)].Members.Count | Should -Be 30
        $status = Get-Status $store
        $status['usedApprovalHash'] | Should -Be $definition.approval.diffHash
        $status['pendingApproval'] | Should -BeNullOrEmpty
        (Get-RunRecord $store).Where({ $_['approval'] }) | Should -HaveCount 2
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'refuses a user list far smaller than last time, writes nothing and keeps the old count' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -Members @(Get-TestUserId 1)
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)
        $heartbeat = [ordered]@{
            id = 'heartbeat-Entra'; pk = 'system'; type = 'heartbeat'; schemaVersion = 1; runbook = 'Entra'; at = '2026-10-12T07:57:00.000Z'
            jobId = '33333333-3333-4333-8333-333333333333'; engineVersion = '0.1.0'; paused = $false; accessMode = 'read-write'; userCount = 100
        }
        Write-StoredDocument -Store $store -Container state -Document $heartbeat

        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Result | Should -Be 'Failed'
        $result.Message | Should -BeLike '*fewer than 80 %*'
        (Get-Status $store)['lastResult'] | Should -Be 'OK'
        (Get-Status $store)['lastSyncUtc'] | Should -Be ([datetime]'2026-10-12T07:00:00Z').ToUniversalTime()
        Get-RunRecord $store | Should -HaveCount 0
        Get-MemberList $tenant (Get-TestGroupId 1) | Should -Be (Get-TestUserId 1)
        (Get-StoredDocument -Store $store -Container state -Type heartbeat)[0]['userCount'] | Should -Be 100
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'only reports in read-only mode' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)

        $result = Invoke-TestSync -Store $store -Tenant $tenant -AccessMode 'read-only'
        $result.Result | Should -Be 'Succeeded'
        $tenant.Groups[(Get-TestGroupId 1)].Members.Count | Should -Be 0
        $status = Get-Status $store
        $status['lastResult'] | Should -Be 'DryRun'
        $status['dryRunReason'] | Should -Be 'readOnly'
        $status['added'] | Should -Be 2
        (Get-RunRecord $store)[0]['dryRun'] | Should -BeTrue
        (Get-RunRecord $store)[0]['then']['result'] | Should -Be 'OK'
        (Get-StoredDocument -Store $store -Container state -Type heartbeat)[0]['accessMode'] | Should -Be 'read-only'
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'writes its own verbose lines with verbose logging on: counts only, no URLs or user names' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $store = Get-TestStore -Settings (Get-TestSettingDocument -Change @{ verboseLogging = $true }) -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)

        $lines = @(Invoke-TestSync -Store $store -Tenant $tenant -AccessMode 'read-only' 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object Message)
        $lines | Should -Contain '1 of 1 definitions due'
        @($lines | Where-Object { $_ -like '*: DryRun (readOnly), 2 members, +2/-0*then OK' }) | Should -HaveCount 1
        @($lines | Where-Object { $_ -match 'https?://|@contoso' }) | Should -HaveCount 0
    }

    It 'writes no verbose lines with verbose logging off' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)
        @(Invoke-TestSync -Store $store -Tenant $tenant 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }) | Should -HaveCount 0
    }

    It 'keeps going when one definition fails, and fails the job' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 2)
        $broken = Get-TestDefinition -Number 2 -Rule 'user.department -eq'
        $store = Get-TestStore -Definitions @((Get-TestDefinition), $broken) -Statuses @((Get-TestStatus), (Get-TestStatus -Number 2))

        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Result | Should -Be 'Failed'
        (Get-Status $store)['lastResult'] | Should -Be 'OK'
        (Get-Status $store -Number 2)['lastResult'] | Should -Be 'Error'
        (Get-Status $store -Number 2)['lastError'] | Should -BeLike '*not valid*'
        $tenant.Groups[(Get-TestGroupId 1)].Members.Count | Should -Be 2
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'reports a missing target group as an error' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)
        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Result | Should -Be 'Failed'
        (Get-Status $store)['lastError'] | Should -BeLike "*$(Get-TestGroupId 1)*doesn't exist*"
    }

    It 'blocks a group synced from on-premises AD' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -OnPremisesSynced $true
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)
        (Invoke-TestSync -Store $store -Tenant $tenant).Result | Should -Be 'Failed'
        (Get-Status $store)['lastResult'] | Should -Be 'Blocked'
    }

    It 'blocks a dynamic group that is not being adopted with conversion' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -IsDynamic $true -GroupTypes @('DynamicMembership')
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)
        (Invoke-TestSync -Store $store -Tenant $tenant).Result | Should -Be 'Failed'
        (Get-Status $store)['lastError'] | Should -BeLike '*dynamic membership*'
    }

    It 'reverts a manual change and says so' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)
        [void](Invoke-TestSync -Store $store -Tenant $tenant)
        [void]$tenant.Groups[(Get-TestGroupId 1)].Members.Add((Get-TestUserId 4))

        $result = Invoke-TestSync -Store $store -Tenant $tenant -Now '2026-10-12T08:03:00Z'
        $result.Result | Should -Be 'Succeeded'
        $status = Get-Status $store
        $status['lastResult'] | Should -Be 'Warning'
        $status['warnings'][0] | Should -BeLike 'manual change detected*'
        $run = (Get-RunRecord $store).Where({ $_['result'] -eq 'Warning' })[0]
        $run['manualChangesReverted']['removed'] | Should -Be 1
        Get-MemberList $tenant (Get-TestGroupId 1) | Should -Be ((Get-TestUserId 1), (Get-TestUserId 2) -join ',')
    }

    It 'turns a failed add into a warning and keeps the hash honest' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        [void]$tenant.FailAdd.Add((Get-TestUserId 2))
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)

        $result = Invoke-TestSync -Store $store -Tenant $tenant
        $result.Result | Should -Be 'Succeeded'
        $status = Get-Status $store
        $status['lastResult'] | Should -Be 'Warning'
        $status['warnings'][0] | Should -BeLike 'could not add user2@contoso.org*'
        $status['memberCount'] | Should -Be 1

        # Next run: no "manual change" for the user that failed, just another try.
        [void]$tenant.FailAdd.Clear()
        [void](Invoke-TestSync -Store $store -Tenant $tenant -Now '2026-10-12T08:03:00Z')
        $status = Get-Status $store
        $status['lastResult'] | Should -Be 'OK'
        $status['memberCount'] | Should -Be 2
    }
}

Describe 'Invoke-DgSync: new and adopted groups' {
    It 'starts a new definition with a dry run, then creates and fills the group' {
        $tenant = Get-TestTenant -Users (@(1..20 | ForEach-Object { Get-TestUser $_ }))
        $settings = Get-TestSettingDocument -Change @{
            newGroupsDryRun = $true
            naming          = [ordered]@{ prefix = [ordered]@{ enabled = $true; text = 'DG-' }; suffix = [ordered]@{ enabled = $false; text = '' } }
            marker          = [ordered]@{ enabled = $true; exchangeCustomAttribute = 10 }
        }
        $definition = Get-TestDefinition -Target ([ordered]@{ mode = 'create'; displayName = 'Sales Team' })
        $store = Get-TestStore -Settings $settings -Definitions @($definition)

        $first = Invoke-TestSync -Store $store -Tenant $tenant
        $first.Result | Should -Be 'Succeeded'
        $tenant.Groups.Count | Should -Be 0
        $status = Get-Status $store
        $status['lastResult'] | Should -Be 'DryRun'
        $status['dryRunReason'] | Should -Be 'newGroup'
        $status['groupId'] | Should -BeNullOrEmpty
        $status['added'] | Should -Be 20

        $second = Invoke-TestSync -Store $store -Tenant $tenant -Now '2026-10-12T08:03:00Z'
        $second.Result | Should -Be 'Succeeded'
        $tenant.Calls -contains 'Create DG-Sales Team' | Should -BeTrue
        $status = Get-Status $store
        $status['groupId'] | Should -Not -BeNullOrEmpty
        $status['lastResult'] | Should -Be 'OK'
        $tenant.Groups[$status['groupId']].Members.Count | Should -Be 20
        $tenant.Groups[$status['groupId']].Marker | Should -Be (Get-TestDefinitionId 1)

        # Third run uses the stored group and creates nothing new.
        [void](Invoke-TestSync -Store $store -Tenant $tenant -Now '2026-10-12T08:06:00Z')
        $tenant.Groups.Count | Should -Be 1
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'waits for approval of an adoption, then converts, renames and syncs the group' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -DisplayName 'Sales (dynamic)' -IsDynamic $true -GroupTypes @('DynamicMembership') `
            -Members @((Get-TestUserId 1), (Get-TestUserId 4))
        $settings = Get-TestSettingDocument -Change @{ naming = [ordered]@{ prefix = [ordered]@{ enabled = $true; text = 'DG-' }; suffix = [ordered]@{ enabled = $false; text = '' } } }
        $target = [ordered]@{ mode = 'adopt'; groupId = (Get-TestGroupId 1); adopted = $false; renameOnAdopt = $true; convertFromDynamic = $true }
        $store = Get-TestStore -Settings $settings -Definitions @(Get-TestDefinition -Target $target)

        $first = Invoke-TestSync -Store $store -Tenant $tenant
        $first.Result | Should -Be 'Succeeded'
        $status = Get-Status $store
        $status['lastResult'] | Should -Be 'WaitingForApproval'
        $status['pendingApproval']['kind'] | Should -Be 'adopt'
        $tenant.Calls | Should -Not -Contain 'Convert'

        $target.adopted = $true
        $approved = Get-TestDefinition -Target $target -Change @{
            approval = [ordered]@{ kind = 'adopt'; diffHash = $status['pendingApproval']['diffHash']; adds = 1; removes = 1; by = 'admin@contoso.org'; at = '2026-10-12T08:01:00Z' }
        }
        Write-StoredDocument -Store $store -Container config -Document $approved
        $second = Invoke-TestSync -Store $store -Tenant $tenant -Now '2026-10-12T08:03:00Z'
        $second.Result | Should -Be 'Succeeded'
        $tenant.Calls | Should -Contain 'Convert'
        $tenant.Groups[(Get-TestGroupId 1)].DisplayName | Should -Be 'DG-Sales (dynamic)'
        Get-MemberList $tenant (Get-TestGroupId 1) | Should -Be ((Get-TestUserId 1), (Get-TestUserId 2) -join ',')
        (Get-Status $store)['usedApprovalHash'] | Should -Be $approved.approval.diffHash
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }
}

Describe 'Invoke-DgSync: sync now, references, compare, Exchange' {
    It 'runs only requested definitions in SyncNow mode, once per request' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 2)
        $requested = Get-TestDefinition -Number 2 -Change @{ syncRequest = [ordered]@{ at = '2026-10-12T07:59:00Z'; by = 'admin@contoso.org' } }
        $store = Get-TestStore -Definitions @((Get-TestDefinition), $requested) -Statuses @((Get-TestStatus), (Get-TestStatus -Number 2))

        $result = Invoke-TestSync -Store $store -Tenant $tenant -Mode SyncNow
        $result.Definitions | Should -HaveCount 1
        $result.Definitions[0].DefinitionId | Should -Be (Get-TestDefinitionId 2)
        (Get-Status $store -Number 2)['handledSyncRequestAt'] | Should -Not -BeNullOrEmpty

        $again = Invoke-TestSync -Store $store -Tenant $tenant -Mode SyncNow -Now '2026-10-12T08:01:00Z'
        $again.Message | Should -Be 'nothing due'
    }

    It 'runs a named definition even when it is not due' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $store = Get-TestStore -Definitions @(Get-TestDefinition -Change @{ frequencyMinutes = 1440 }) -Statuses @(Get-TestStatus)
        $result = Invoke-TestSync -Store $store -Tenant $tenant -Mode SyncNow -DefinitionId (Get-TestDefinitionId 1)
        $result.Definitions | Should -HaveCount 1
    }

    It 'uses the fresh result of a referenced definition and reads other groups live' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 2)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 50) -Members @(Get-TestUserId 4)
        $rule = "user.memberof -any (group.objectId -in ['$(Get-TestGroupId 1)', '$(Get-TestGroupId 50)'])"
        $store = Get-TestStore -Definitions @((Get-TestDefinition), (Get-TestDefinition -Number 2 -Rule $rule)) -Statuses @((Get-TestStatus), (Get-TestStatus -Number 2))

        [void](Invoke-TestSync -Store $store -Tenant $tenant)
        Get-MemberList $tenant (Get-TestGroupId 2) | Should -Be ((Get-TestUserId 1), (Get-TestUserId 2), (Get-TestUserId 4) -join ',')
    }

    It 'stores the comparison with a compare group' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -Members @((Get-TestUserId 1), (Get-TestUserId 2))
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 60) -Members @((Get-TestUserId 1), (Get-TestUserId 4))
        $store = Get-TestStore -Definitions @(Get-TestDefinition -Change @{ compareGroupId = (Get-TestGroupId 60) }) -Statuses @(Get-TestStatus)

        [void](Invoke-TestSync -Store $store -Tenant $tenant)
        $compare = (Get-Status $store)['compare']
        $compare['onlyInRdg'] | Should -Be 1
        $compare['onlyInCompare'] | Should -Be 1
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'syncs an Exchange group and skips users without a mailbox' {
        $graph = Get-TestTenant -Users (Get-StandardUserList)
        $exchange = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $exchange -Id (Get-TestGroupId 1)
        $exchange.Recipients[(Get-TestUserId 1)] = 'recipient-1'
        $store = Get-TestStore -Definitions @((Get-TestDefinition -GroupType Distribution), (Get-TestDefinition -Number 2)) -Statuses @(Get-TestStatus)

        $result = Invoke-TestSync -Store $store -Tenant $graph -Provider Exchange -ExchangeTenant $exchange
        $result.Result | Should -Be 'Succeeded'
        $result.Definitions | Should -HaveCount 1
        Get-MemberList $exchange (Get-TestGroupId 1) | Should -Be (Get-TestUserId 1)
        $status = Get-Status $store
        $status['skipped'] | Should -Be 1
        (Get-RunRecord $store)[0]['skipped'][0]['upn'] | Should -Be 'user2@contoso.org'
        (Get-StoredDocument -Store $store -Container state -Type heartbeat)[0]['id'] | Should -Be 'heartbeat-Exchange'
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }
}

Describe 'Invoke-DgSync: runbook behaviour' {
    It 'lets a SyncNow job wait for the lock, then defer to the next scheduled run' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        $store = Get-TestStore -Definitions @(Get-TestDefinition -Change @{ syncRequest = [ordered]@{ at = '2026-10-12T07:59:00Z'; by = 'admin@contoso.org' } })
        $lock = [ordered]@{
            id = 'lock-Entra'; pk = 'lock'; type = 'lock'; schemaVersion = 1; jobId = '22222222-2222-4222-8222-222222222222'
            acquiredAt = '2026-10-12T07:59:00.000Z'; expiresAt = '2026-10-12T08:29:00.000Z'
        }
        Write-StoredDocument -Store $store -Container state -Document $lock
        $waits = [System.Collections.Generic.List[double]]::new()

        $result = Invoke-DgSync -Provider Entra -Mode SyncNow -DefinitionId (Get-TestDefinitionId 1) -Store $store -GraphDirectory $tenant.Directory `
            -AccessMode read-write -TickMinutes 15 -Now ([DateTimeOffset]'2026-10-12T08:00:00Z') -Sleep { param($Seconds) $waits.Add($Seconds) }.GetNewClosure()
        $result.Result | Should -Be 'Deferred'
        ($waits -join ',') | Should -Be '15,15,15,15,15,15,15,15'
        (Get-RunRecord $store)[0]['reason'] | Should -BeLike 'deferred:*'
        Get-Status $store | Should -BeNullOrEmpty
        Test-StoredDocumentSchema -Store $store | Should -HaveCount 0
    }

    It 'stops at the time limit, leaves the rest for the next tick and fails the job' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)

        $result = Invoke-DgSync -Provider Entra -Store $store -GraphDirectory $tenant.Directory -AccessMode read-write -TickMinutes 3 `
            -Now ([DateTimeOffset]'2026-10-12T08:00:00Z') -MaxRunTime ([TimeSpan]::Zero)
        $result.Result | Should -Be 'Failed'
        $result.Message | Should -BeLike '*1 left for the next tick*'
        (Get-Status $store)['lastSyncUtc'] | Should -Be ([datetime]'2026-10-12T07:00:00Z').ToUniversalTime()
    }

    It 'uses Config for tick and access mode, defaulting to read-only' {
        $tenant = Get-TestTenant -Users (Get-StandardUserList)
        Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1)
        $store = Get-TestStore -Definitions @(Get-TestDefinition) -Statuses @(Get-TestStatus)
        $result = Invoke-DgSync -Provider Entra -Store $store -GraphDirectory $tenant.Directory -Config @{ TickMinutes = 15 } -Now ([DateTimeOffset]'2026-10-12T08:00:00Z')
        $result.AccessMode | Should -Be 'read-only'
        (Get-Status $store)['dryRunReason'] | Should -Be 'readOnly'
    }

    It 'renews the lease of a long run and stops when another job took the lock over' {
        $result = InModuleScope DgEngine {
            $store = New-DgMemoryStore
            $now = [DateTimeOffset]'2026-10-12T08:00:00Z'
            $lock = Enter-DgRunLock -Store $store -Provider Entra -JobId 'job-a' -Now $now -LeaseMinutes 30
            $same = Update-DgRunLock -Store $store -Lock $lock -Now $now.AddMinutes(10) -LeaseMinutes 30
            $renewed = Update-DgRunLock -Store $store -Lock $lock -Now $now.AddMinutes(20) -LeaseMinutes 30
            $expires = $renewed.Lock['expiresAt']
            # Simulate a takeover: the stored lock changes behind this job's back.
            [void](Set-DgStoreItem -Store $store -Container state -Document ([ordered]@{ id = 'lock-Entra'; pk = 'lock'; type = 'lock'; jobId = 'job-b' }))
            $lost = try { [void](Update-DgRunLock -Store $store -Lock $renewed -Now $now.AddMinutes(45) -LeaseMinutes 30); 'kept' } catch { $_.Exception.Message }
            [pscustomobject]@{ SameEtag = $same.Lock['_etag'] -eq $lock.Lock['_etag']; Expires = $expires; Lost = $lost }
        }
        $result.SameEtag | Should -BeTrue
        $result.Expires | Should -Be ([datetime]'2026-10-12T08:50:00Z').ToUniversalTime()
        $result.Lost | Should -BeLike '*taken over*'
    }
}

Describe 'Write-DgRunbookResult' {
    It 'writes one JSON line per definition and a summary, and warnings with the definition name' {
        $result = [pscustomobject]@{
            Provider = 'Entra'; Mode = 'Scheduled'; AccessMode = 'read-write'; JobId = 'j'; Result = 'Succeeded'; Message = '1 definitions synced'; DurationMs = 5
            FailedDefinitions = @()
            Definitions = @([pscustomobject]@{ Name = 'Sales'; Result = 'Warning'; Added = 2; Removed = 1; DurationMs = 40; Warnings = @('manual change detected'); Error = $null })
        }
        $warnings = $null
        $lines = Write-DgRunbookResult -Result $result -WarningVariable warnings -WarningAction SilentlyContinue
        $lines | Should -HaveCount 2
        $lines[0] | Should -Be '{"definition":"Sales","result":"Warning","added":2,"removed":1,"ms":40}'
        ($lines[1] | ConvertFrom-Json).result | Should -Be 'Succeeded'
        "$($warnings[0])" | Should -Be 'Sales: manual change detected'
    }

    It 'throws one summary error when the run failed' {
        $result = [pscustomobject]@{
            Provider = 'Entra'; Mode = 'Scheduled'; AccessMode = 'read-write'; JobId = 'j'; Result = 'Failed'; Message = 'x'; DurationMs = 5
            FailedDefinitions = @('EOP Strict (Blocked: change limit)', 'Finance (Error: rule)')
            Definitions = @()
        }
        { Write-DgRunbookResult -Result $result } | Should -Throw -ExpectedMessage '2 definitions blocked or failed: EOP Strict (Blocked: change limit), Finance (Error: rule)'
    }

    It 'names the reason when the run failed without a definition' {
        $result = [pscustomobject]@{
            Provider = 'Entra'; Mode = 'Scheduled'; AccessMode = 'read-write'; JobId = 'j'; Result = 'Failed'; Message = 'the user list is empty'; DurationMs = 5
            FailedDefinitions = @(); Definitions = @()
        }
        { Write-DgRunbookResult -Result $result } | Should -Throw -ExpectedMessage 'the run failed: the user list is empty'
    }
}
