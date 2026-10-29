#Requires -Version 7.4
# The Exchange Online side of the directory adapter (mail-enabled security groups and distribution lists).

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fakes.ps1')

    # Exchange double whose members u1..u4 behave differently on add and remove.
    function Get-MemberFake {
        $fake = Get-FakeExchange -Handler {
            param($Call)
            switch ($Call.Parameters.Member) {
                'r-dup' { @{ FakeError = 'exchange'; Message = 'The recipient "x" is already a member of the group "y".' } }
                'r-gone' { @{ FakeError = 'exchange'; Message = 'The recipient "x" isn''t a member of the group "y".' } }
                'r-bad' { @{ FakeError = 'exchange'; Message = 'Access denied' } }
                default { $null }
            }
        }
        $fake.Directory.Recipients = @{ 'u1' = 'r1'; 'u2' = 'r-dup'; 'u3' = 'r-gone'; 'u4' = 'r-bad' }
        $fake
    }
}

Describe 'Get-DgDirectoryGroup (Exchange)' {
    It 'finds the group by its Entra object ID and uses the Exchange GUID as identity' {
        $fake = Get-FakeExchange -Handler {
            [pscustomobject]@{ ExternalDirectoryObjectId = 'g1'; DisplayName = 'All Bern'; IsDirSynced = $true; Guid = 'ex-guid-1' }
        }
        $group = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryGroup -Directory $D -GroupId 'g1' }
        $group.Identity | Should -Be 'ex-guid-1'
        $group.OnPremisesSynced | Should -BeTrue
        $group.IsDynamic | Should -BeFalse
        $fake.State.Calls[0].Parameters.Filter | Should -Be "ExternalDirectoryObjectId -eq 'g1'"
    }

    It 'returns nothing when no group matches' {
        $fake = Get-FakeExchange -Handler { $null }
        $group = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgDirectoryGroup -Directory $D -GroupId 'gx' }
        $group | Should -BeNullOrEmpty
    }
}

Describe 'Get-DgDirectoryMember (Exchange)' {
    It 'treats mailboxes and mail users as users, everything else not' {
        $fake = Get-FakeExchange -Handler {
            @(
                [pscustomobject]@{ ExternalDirectoryObjectId = 'u1'; RecipientType = 'UserMailbox' },
                [pscustomobject]@{ ExternalDirectoryObjectId = 'u2'; RecipientType = 'MailUser' },
                [pscustomobject]@{ ExternalDirectoryObjectId = 'c1'; RecipientType = 'MailContact' },
                [pscustomobject]@{ ExternalDirectoryObjectId = 'g2'; RecipientType = 'MailUniversalDistributionGroup' }
            )
        }
        $members = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Get-DgDirectoryMember -Directory $D -Group $G }
        ($members | ForEach-Object { "$($_.Id)=$($_.IsUser)" }) -join ',' | Should -Be 'u1=True,u2=True,c1=False,g2=False'
        $fake.State.Calls[0].Parameters.Identity | Should -Be 'guid-g1'
        $fake.State.Calls[0].Parameters.ResultSize | Should -Be 'Unlimited'
    }
}

Describe 'Get-DgRecipientMap' {
    It 'maps lower-case Entra object IDs to recipient GUIDs and keeps the map on the directory' {
        $fake = Get-FakeExchange -Handler {
            @(
                [pscustomobject]@{ ExternalDirectoryObjectId = 'AAA-1'; Guid = 'r1' },
                [pscustomobject]@{ ExternalDirectoryObjectId = ''; Guid = 'r-orphan' },
                [pscustomobject]@{ ExternalDirectoryObjectId = 'bbb-2'; Guid = 'r2' }
            )
        }
        $map = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgRecipientMap -Directory $D }
        $map.Count | Should -Be 2
        $map['aaa-1'] | Should -Be 'r1'
        $fake.Directory.Recipients['bbb-2'] | Should -Be 'r2'
    }
}

Describe 'Add-DgDirectoryMember and Remove-DgDirectoryMember (Exchange)' {
    It 'adds by recipient GUID, accepts existing members and reports users without a recipient' {
        $fake = Get-MemberFake
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Add-DgDirectoryMember -Directory $D -Group $G -UserIds @('u1', 'u2', 'u9') }
        ($result.Succeeded -join ',') | Should -Be 'u1,u2'
        $result.Failed[0].Id | Should -Be 'u9'
        $result.Failed[0].Error | Should -BeLike '*no Exchange recipient*'
        $call = $fake.State.Calls[0]
        $call.Command | Should -Be 'Add-DistributionGroupMember'
        $call.Parameters.Identity | Should -Be 'guid-g1'
        $call.Parameters.Member | Should -Be 'r1'
        $call.Parameters.BypassSecurityGroupManagerCheck | Should -BeTrue
    }

    It 'removes, accepts members that are already gone and reports refusals' {
        $fake = Get-MemberFake
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Remove-DgDirectoryMember -Directory $D -Group $G -UserIds @('u1', 'u3', 'u4') }
        ($result.Succeeded -join ',') | Should -Be 'u1,u3'
        $result.Failed[0].Id | Should -Be 'u4'
        $fake.State.Calls[0].Command | Should -Be 'Remove-DistributionGroupMember'
    }
}

Describe 'New-DgDirectoryGroup (Exchange)' {
    It 'creates a closed distribution list and waits for its Entra object ID' {
        $fake = Get-FakeExchange -Handler {
            param($Call)
            switch ($Call.Command) {
                'New-DistributionGroup' { [pscustomobject]@{ Guid = 'ex-new'; ExternalDirectoryObjectId = '' } }
                'Get-DistributionGroup' {
                    if ($Call.Parameters.ContainsKey('Identity')) {
                        $Call.State.Attempts++
                        $id = if ($Call.State.Attempts -ge 2) { 'entra-new' } else { '' }
                        [pscustomobject]@{ Guid = 'ex-new'; ExternalDirectoryObjectId = $id }
                    } else {
                        [pscustomobject]@{ Guid = 'ex-new'; ExternalDirectoryObjectId = 'entra-new'; DisplayName = 'RDG List' }
                    }
                }
            }
        }
        $group = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { New-DgDirectoryGroup -Directory $D -GroupType Distribution -DisplayName 'RDG List' -MailNickname 'rdg-list' }
        $group.Id | Should -Be 'entra-new'
        $group.Identity | Should -Be 'ex-new'
        ($fake.State.Sleeps -join ',') | Should -Be '5,5'
        $create = $fake.State.Calls[0].Parameters
        $create.Type | Should -Be 'Distribution'
        $create.MemberJoinRestriction | Should -Be 'Closed'
        $create.MemberDepartRestriction | Should -Be 'Closed'
        $create.Alias | Should -Be 'rdg-list'
    }

    It 'creates a mail-enabled security group with type Security' {
        $fake = Get-FakeExchange -Handler { [pscustomobject]@{ Guid = 'ex-sec'; ExternalDirectoryObjectId = 'entra-sec' } }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { [void](New-DgDirectoryGroup -Directory $D -GroupType MailEnabledSecurity -DisplayName 'RDG Sec' -MailNickname 'rdg-sec') }
        $fake.State.Calls[0].Parameters.Type | Should -Be 'Security'
        $fake.State.Sleeps | Should -HaveCount 0
    }

    It 'fails when the object ID never shows up' {
        $fake = Get-FakeExchange -Handler { [pscustomobject]@{ Guid = 'ex-slow'; ExternalDirectoryObjectId = '' } } -CreateWaitAttempts 3
        { InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { New-DgDirectoryGroup -Directory $D -GroupType Distribution -DisplayName 'Slow' -MailNickname 'slow' } } |
            Should -Throw -ExpectedMessage '*ex-slow*no Entra object ID*'
        $fake.State.Sleeps | Should -HaveCount 3
    }

    It 'refuses Graph group types' {
        $fake = Get-FakeExchange -Handler { $null }
        { InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { New-DgDirectoryGroup -Directory $D -GroupType Security -DisplayName 'x' -MailNickname 'x' } } |
            Should -Throw -ExpectedMessage '*MailEnabledSecurity and Distribution*'
    }
}

Describe 'Set-DgDirectoryMarker and ConvertTo-DgAssignedGroup (Exchange)' {
    It 'writes the marker to the configured custom attribute' {
        $fake = Get-FakeExchange -Handler { $null } -MarkerAttribute 5
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Set-DgDirectoryMarker -Directory $D -Group $G -DefinitionId 'def-1' }
        $fake.State.Calls[0].Command | Should -Be 'Set-DistributionGroup'
        $fake.State.Calls[0].Parameters.CustomAttribute5 | Should -Be 'def-1'
    }

    It 'does nothing when no attribute is configured' {
        $fake = Get-FakeExchange -Handler { $null }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup) } { Set-DgDirectoryMarker -Directory $D -Group $G -DefinitionId 'def-1' }
        $fake.State.Calls | Should -HaveCount 0
    }

    It 'cannot convert a dynamic distribution group' {
        $fake = Get-FakeExchange -Handler { $null }
        { InModuleScope DgEngine -Parameters @{ D = $fake.Directory; G = (Get-TestGroup -IsDynamic $true) } { ConvertTo-DgAssignedGroup -Directory $D -Group $G } } |
            Should -Throw -ExpectedMessage '*only Entra dynamic groups*'
    }
}
