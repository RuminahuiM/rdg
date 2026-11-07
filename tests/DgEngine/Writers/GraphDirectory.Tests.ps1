#Requires -Version 7.4
# The Graph side of the directory adapter: reads, member writes, create, convert, marker.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fakes.ps1')
}

Describe 'Get-DgDirectoryUser (Graph)' {
    It 'always selects the base fields, adds the requested ones and pages 999 at a time' {
        $fake = Get-FakeGraph -Handler { @{ value = @(@{ id = 'u1' }) } }
        $users = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryUser -Directory $D -Select @('department', 'city') }
        $users | Should -HaveCount 1
        $uri = $fake.State.Calls[0].Uri
        $uri | Should -BeLike '*/users?$select=accountEnabled,city,department,displayName,id,userPrincipalName,userType&$top=999'
        $uri | Should -Not -BeLike '*$expand*'
    }

    It 'expands the manager ID only when asked' {
        $fake = Get-FakeGraph -Handler { @{ value = @() } }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { [void](Get-DgDirectoryUser -Directory $D -ExpandManager) }
        $fake.State.Calls[0].Uri | Should -BeLike '*&$expand=manager($select=id)'
    }
}

Describe 'Get-DgDirectoryGroup (Graph)' {
    It 'maps the group fields the safety checks need' {
        $fake = Get-FakeGraph -Handler {
            @{ id = 'g1'; displayName = 'Staff'; groupTypes = @('DynamicMembership'); onPremisesSyncEnabled = $null; isAssignableToRole = $true; membershipRule = 'user.city -eq "Bern"' }
        }
        $group = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryGroup -Directory $D -GroupId 'g1' }
        $group.DisplayName | Should -Be 'Staff'
        $group.IsDynamic | Should -BeTrue
        $group.OnPremisesSynced | Should -BeFalse
        $group.IsAssignableToRole | Should -BeTrue
        $group.Identity | Should -Be 'g1'
    }

    It 'returns nothing for a group that does not exist' {
        $fake = Get-FakeGraph -Handler { @{ FakeError = 404; Message = 'Request_ResourceNotFound' } }
        $group = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryGroup -Directory $D -GroupId 'missing' }
        $group | Should -BeNullOrEmpty
    }

    It 'throws other errors' {
        $fake = Get-FakeGraph -Handler { @{ FakeError = 403; Message = 'Authorization_RequestDenied' } }
        { InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryGroup -Directory $D -GroupId 'g1' } } |
            Should -Throw -ExpectedMessage '*RequestDenied*'
    }
}

Describe 'Get-DgDirectoryMember (Graph)' {
    It 'marks users and non-users' {
        $fake = Get-FakeGraph -Handler {
            @{
                value = @(
                    @{ id = 'u1'; '@odata.type' = '#microsoft.graph.user' },
                    @{ id = 'd1'; '@odata.type' = '#microsoft.graph.device' }
                )
            }
        }
        $members = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Get-DgDirectoryMember -Directory $D -Group $G }
        ($members | ForEach-Object { "$($_.Id)=$($_.IsUser)" }) -join ',' | Should -Be 'u1=True,d1=False'
    }
}

Describe 'Get-DgDirectoryUserMemberId' {
    It 'reads transitive user members when asked' {
        $fake = Get-FakeGraph -Handler { @{ value = @(@{ id = 'u1' }, @{ id = 'u2' }) } }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryUserMemberId -Directory $D -GroupId 'g9' -Transitive $true }
        $result.Found | Should -BeTrue
        ($result.UserIds -join ',') | Should -Be 'u1,u2'
        $fake.State.Calls[0].Uri | Should -BeLike '*/groups/g9/transitiveMembers/microsoft.graph.user?*'
    }

    It 'reads direct members otherwise' {
        $fake = Get-FakeGraph -Handler { @{ value = @() } }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { [void](Get-DgDirectoryUserMemberId -Directory $D -GroupId 'g9' -Transitive $false) }
        $fake.State.Calls[0].Uri | Should -BeLike '*/groups/g9/members/microsoft.graph.user?*'
    }

    It 'reports a missing group as not found' {
        $fake = Get-FakeGraph -Handler { @{ FakeError = 404; Message = 'not found' } }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryUserMemberId -Directory $D -GroupId 'gone' -Transitive $true }
        $result.Found | Should -BeFalse
    }
}

Describe 'Add-DgDirectoryMember (Graph)' {
    It 'adds in chunks of 20 through members@odata.bind' {
        $fake = Get-FakeGraph -Handler { $null }
        $ids = [string[]]@(1..45 | ForEach-Object { "u$_" })
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup); I = $ids } { Add-DgDirectoryMember -Directory $D -Group $G -UserIds $I }
        $result.Succeeded | Should -HaveCount 45
        $result.Failed | Should -HaveCount 0
        $fake.State.Calls | Should -HaveCount 3
        $fake.State.Calls[0].Method | Should -Be 'PATCH'
        $fake.State.Calls[0].Uri | Should -BeLike '*/groups/g1'
        $fake.State.Calls[0].Body['members@odata.bind'] | Should -HaveCount 20
        $fake.State.Calls[2].Body['members@odata.bind'] | Should -HaveCount 5
        $fake.State.Calls[0].Body['members@odata.bind'][0] | Should -Be 'https://graph.microsoft.com/v1.0/directoryObjects/u1'
    }

    It 'falls back to single adds when a chunk fails' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            if ($Call.Method -eq 'PATCH') { return @{ FakeError = 400; Message = 'One or more added object references already exist' } }
            switch -Wildcard ($Call.Body['@odata.id']) {
                '*/u2' { @{ FakeError = 400; Message = "One or more added object references already exist for the following modified properties: 'members'." } }
                '*/u3' { @{ FakeError = 404; Message = 'Resource u3 does not exist' } }
                default { $null }
            }
        }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Add-DgDirectoryMember -Directory $D -Group $G -UserIds @('u1', 'u2', 'u3') }
        ($result.Succeeded -join ',') | Should -Be 'u1,u2'
        $result.Failed | Should -HaveCount 1
        $result.Failed[0].Id | Should -Be 'u3'
        # one PATCH, then u1, u2 once each and u3 twice
        $fake.State.Calls | Should -HaveCount 5
        $fake.State.Calls[1].Uri | Should -BeLike '*/groups/g1/members/$ref'
    }

    It 'changes nothing with -WhatIf' {
        $fake = Get-FakeGraph -Handler { $null }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Add-DgDirectoryMember -Directory $D -Group $G -UserIds @('u1') -WhatIf }
        $fake.State.Calls | Should -HaveCount 0
        $result.Succeeded | Should -HaveCount 0
    }
}

Describe 'Remove-DgDirectoryMember (Graph)' {
    It 'removes through $batch, counts 404 as done and retries the rest one by one' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            if ($Call.Uri -like '*$batch') {
                return @{
                    responses = @(
                        @{ id = '0'; status = 204 },
                        @{ id = '1'; status = 404 },
                        @{ id = '2'; status = 500 }
                    )
                }
            }
            @{ FakeError = 404; Message = 'not a member' }
        }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Remove-DgDirectoryMember -Directory $D -Group $G -UserIds @('u1', 'u2', 'u3') }
        ($result.Succeeded -join ',') | Should -Be 'u1,u2,u3'
        $fake.State.Calls | Should -HaveCount 2
        $batch = $fake.State.Calls[0]
        $batch.Body.requests | Should -HaveCount 3
        $batch.Body.requests[2].url | Should -Be '/groups/g1/members/u3/$ref'
        $fake.State.Calls[1].Method | Should -Be 'DELETE'
    }

    It 'reports a member that cannot be removed' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            if ($Call.Uri -like '*$batch') { return @{ responses = @(@{ id = '0'; status = 403 }) } }
            @{ FakeError = 403; Message = 'Insufficient privileges' }
        }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Remove-DgDirectoryMember -Directory $D -Group $G -UserIds @('u1') }
        $result.Succeeded | Should -HaveCount 0
        $result.Failed[0].Error | Should -BeLike '*Insufficient privileges*'
    }

    It 'sends 25 removals as two batches' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            @{ responses = @($Call.Body.requests | ForEach-Object { @{ id = $_.id; status = 204 } }) }
        }
        $ids = [string[]]@(1..25 | ForEach-Object { "u$_" })
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup); I = $ids } { Remove-DgDirectoryMember -Directory $D -Group $G -UserIds $I }
        $result.Succeeded | Should -HaveCount 25
        $fake.State.Calls | Should -HaveCount 2
        $fake.State.Calls[1].Body.requests | Should -HaveCount 5
    }
}

Describe 'New-DgDirectoryGroup (Graph)' {
    It 'creates a security group and reads it back' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            if ($Call.Method -eq 'POST') { return @{ id = 'new1' } }
            @{ id = 'new1'; displayName = 'RDG Bern'; groupTypes = @() }
        }
        $group = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { New-DgDirectoryGroup -Directory $D -GroupType Security -DisplayName 'RDG Bern' -MailNickname 'rdg-bern' }
        $group.Id | Should -Be 'new1'
        $body = $fake.State.Calls[0].Body
        $body.mailEnabled | Should -BeFalse
        $body.securityEnabled | Should -BeTrue
        $body.ContainsKey('groupTypes') | Should -BeFalse
        $fake.State.Calls[1].Uri | Should -BeLike '*/groups/new1?*'
    }

    It 'creates a private Microsoft 365 group' {
        $fake = Get-FakeGraph -Handler { @{ id = 'm1'; groupTypes = @('Unified') } }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { [void](New-DgDirectoryGroup -Directory $D -GroupType Microsoft365 -DisplayName 'RDG Team' -MailNickname 'rdg-team') }
        $body = $fake.State.Calls[0].Body
        $body.mailEnabled | Should -BeTrue
        $body.groupTypes -join ',' | Should -Be 'Unified'
        $body.visibility | Should -Be 'Private'
    }

    It 'refuses group types that need Exchange' {
        $fake = Get-FakeGraph -Handler { $null }
        { InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { New-DgDirectoryGroup -Directory $D -GroupType Distribution -DisplayName 'x' -MailNickname 'x' } } |
            Should -Throw -ExpectedMessage '*Security and Microsoft365*'
    }
}

Describe 'Rename-DgDirectoryGroup and ConvertTo-DgAssignedGroup (Graph)' {
    It 'renames with a PATCH of displayName' {
        $fake = Get-FakeGraph -Handler { $null }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Rename-DgDirectoryGroup -Directory $D -Group $G -DisplayName 'New name' }
        $fake.State.Calls[0].Method | Should -Be 'PATCH'
        $fake.State.Calls[0].Body.displayName | Should -Be 'New name'
    }

    It 'drops DynamicMembership, keeps other types and pauses rule processing' {
        $fake = Get-FakeGraph -Handler { $null }
        $group = Get-TestGroup -IsDynamic $true -GroupTypes @('Unified', 'DynamicMembership')
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = $group } { ConvertTo-DgAssignedGroup -Directory $D -Group $G }
        $body = $fake.State.Calls[0].Body
        ($body.groupTypes -join ',') | Should -Be 'Unified'
        $body.membershipRuleProcessingState | Should -Be 'Paused'
    }

    It 'leaves an assigned group alone' {
        $fake = Get-FakeGraph -Handler { $null }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { ConvertTo-DgAssignedGroup -Directory $D -Group $G }
        $fake.State.Calls | Should -HaveCount 0
    }
}

Describe 'Set-DgDirectoryMarker (Graph)' {
    It 'writes the definition ID to the configured extension' {
        $fake = Get-FakeGraph -Handler { $null } -MarkerExtension 'extension_abc_rdgDefinition'
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Set-DgDirectoryMarker -Directory $D -Group $G -DefinitionId 'def-1' }
        $fake.State.Calls[0].Body['extension_abc_rdgDefinition'] | Should -Be 'def-1'
    }

    It 'clears the marker with an empty ID' {
        $fake = Get-FakeGraph -Handler { $null } -MarkerExtension 'extension_abc_rdgDefinition'
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Set-DgDirectoryMarker -Directory $D -Group $G -DefinitionId '' }
        $fake.State.Calls[0].Body.ContainsKey('extension_abc_rdgDefinition') | Should -BeTrue
        $fake.State.Calls[0].Body['extension_abc_rdgDefinition'] | Should -BeNullOrEmpty
    }

    It 'does nothing without a configured extension' {
        $fake = Get-FakeGraph -Handler { $null }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Set-DgDirectoryMarker -Directory $D -Group $G -DefinitionId 'def-1' }
        $fake.State.Calls | Should -HaveCount 0
    }
}

Describe 'Find-DgDirectoryObject (Graph)' {
    It 'searches users by prefix with escaped quotes and at most 25 results' {
        $fake = Get-FakeGraph -Handler { @{ value = @(1..30 | ForEach-Object { @{ id = "u$_" } }) } }
        $found = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Find-DgDirectoryObject -Directory $D -Kind User -Search "O'Brien" }
        $found | Should -HaveCount 25
        $uri = [System.Uri]::UnescapeDataString($fake.State.Calls[0].Uri)
        $uri | Should -BeLike "*/users?`$filter=startswith(displayName,'O''Brien') or startswith(userPrincipalName,'O''Brien') or startswith(mail,'O''Brien')&`$select=*&`$top=25"
    }

    It 'searches groups with the fields the picker needs' {
        $fake = Get-FakeGraph -Handler { @{ value = @() } }
        $found = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { , (Find-DgDirectoryObject -Directory $D -Kind Group -Search 'Sal') }
        $found.Count | Should -Be 0
        [System.Uri]::UnescapeDataString($fake.State.Calls[0].Uri) | Should -BeLike '*/groups?*membershipRule*'
    }
}

Describe 'Get-DgGroupKind' {
    It 'names the group type from the Graph flags' -ForEach @(
        @{ Types = @('Unified'); Mail = $true; Security = $false; Kind = 'Microsoft365' }
        @{ Types = @(); Mail = $false; Security = $true; Kind = 'Security' }
        @{ Types = @(); Mail = $true; Security = $true; Kind = 'MailEnabledSecurity' }
        @{ Types = @(); Mail = $true; Security = $false; Kind = 'Distribution' }
        @{ Types = @(); Mail = $false; Security = $false; Kind = 'Other' }
    ) {
        InModuleScope DgEngine -Parameters @{ T = $Types; M = $Mail; S = $Security } { Get-DgGroupKind -GroupTypes $T -MailEnabled $M -SecurityEnabled $S } | Should -Be $Kind
    }

    It 'is part of what Get-DgDirectoryGroup returns' {
        $fake = Get-FakeGraph -Handler { @{ id = 'g1'; displayName = 'List'; groupTypes = @(); mailEnabled = $true; securityEnabled = $false; mail = 'list@contoso.org' } }
        $group = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryGroup -Directory $D -GroupId 'g1' }
        $group.GroupType | Should -Be 'Distribution'
        $group.Mail | Should -Be 'list@contoso.org'
    }

    It 'reads a dynamic Microsoft 365 group (two group types) as Microsoft365 and dynamic' {
        $fake = Get-FakeGraph -Handler { @{ id = 'g2'; displayName = 'Team'; groupTypes = @('DynamicMembership', 'Unified'); mailEnabled = $true; securityEnabled = $true; membershipRule = 'user.department -eq "IT"' } }
        $group = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryGroup -Directory $D -GroupId 'g2' }
        $group.GroupType | Should -Be 'Microsoft365'
        $group.IsDynamic | Should -BeTrue
        ($group.GroupTypes -join ',') | Should -Be 'DynamicMembership,Unified'
    }
}

Describe 'Get-DgDirectoryObjectById (Graph)' {
    It 'reads users and groups through one $batch with the fields it needs, de-duplicated' {
        $fake = Get-FakeGraph -Handler {
            $responses = @(
                @{ id = '0'; status = 200; body = @{ id = 'a'; displayName = 'Alex'; userPrincipalName = 'alex@contoso.org' } }
                @{ id = '1'; status = 404; body = @{} }
                @{ id = '2'; status = 200; body = @{ id = 'g'; displayName = 'Sales' } }
            )
            @{ responses = $responses }
        }
        $found = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { , (Get-DgDirectoryObjectById -Directory $D -UserIds @('A', 'a', 'b') -GroupIds @('G')) }
        $found.Count | Should -Be 2
        $fake.State.Calls | Should -HaveCount 1
        $fake.State.Calls[0].Method | Should -Be 'POST'
        $fake.State.Calls[0].Uri | Should -BeLike '*/$batch'
        $urls = @($fake.State.Calls[0].Body.requests | ForEach-Object { $_.url })
        ($urls -join ' ') | Should -Be '/users/a?$select=id,displayName,userPrincipalName /users/b?$select=id,displayName,userPrincipalName /groups/g?$select=id,displayName'
    }

    It 'splits into batches of 20' {
        $fake = Get-FakeGraph -Handler { @{ responses = @() } }
        $ids = 1..45 | ForEach-Object { "id$_" }
        $null = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; I = $ids } { Get-DgDirectoryObjectById -Directory $D -UserIds $I }
        $fake.State.Calls | Should -HaveCount 3
        @($fake.State.Calls[2].Body.requests).Count | Should -Be 5
    }

    It 'throws on a failed entry other than 404' {
        $fake = Get-FakeGraph -Handler { @{ responses = @(@{ id = '0'; status = 403; body = @{} }) } }
        { InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryObjectById -Directory $D -UserIds @('a') } } | Should -Throw '*status 403*'
    }

    It 'makes no call without IDs' {
        $fake = Get-FakeGraph -Handler { throw 'no call expected' }
        $found = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { , (Get-DgDirectoryObjectById -Directory $D) }
        $found.Count | Should -Be 0
        $fake.State.Calls | Should -HaveCount 0
    }
}
