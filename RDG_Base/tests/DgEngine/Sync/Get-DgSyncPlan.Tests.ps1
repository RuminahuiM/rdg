#Requires -Version 7.4
# One or more tests per safety rule in the Engine design.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force

    # Builds a plan for a group whose current user members are $Current and whose desired
    # members are $Desired (both lists of IDs).
    function Invoke-Plan {
        param(
            [string[]] $Current = @(),
            [string[]] $Desired = @(),
            [hashtable] $Definition = @{},
            [hashtable] $Group = @{},
            [hashtable] $Status = $null,
            [string] $AccessMode = 'read-write',
            [switch] $FirstFill,
            [switch] $NewGroupDryRun,
            [string[]] $Warnings = @()
        )
        InModuleScope DgEngine -Parameters @{ C = $Current; D = $Desired; Def = $Definition; G = $Group; S = $Status; A = $AccessMode; F = [bool]$FirstFill; NG = [bool]$NewGroupDryRun; W = $Warnings } {
            $set = [System.Collections.Generic.HashSet[string]]::new([string[]]@($D), [System.StringComparer]::OrdinalIgnoreCase)
            $desiredObject = [pscustomobject]@{ MemberIds = $set; Warnings = $W }
            $currentMembers = @($C | ForEach-Object { [pscustomobject]@{ Id = $_; IsUser = $true } })
            $diff = Get-DgMemberDiff -DesiredIds $set -CurrentMembers $currentMembers
            $settings = @{ ChangeLimitPercent = 50; ChangeLimitMinChanges = 10 }
            Get-DgSyncPlan -Definition $Def -Desired $desiredObject -Diff $diff -Group $G -Settings $settings -Status $S -AccessMode $A -FirstFill:$F -NewGroupDryRun:$NG
        }
    }
    function Get-Range { param([int] $From, [int] $To) [string[]]@($From..$To | ForEach-Object { "u$_" }) }
}

Describe 'Get-DgSyncPlan' {
    It 'writes a small change' {
        $plan = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 22)
        $plan.Result | Should -Be 'OK'
        $plan.Write | Should -BeTrue
        ($plan.Adds) -join ',' | Should -Be 'u21,u22'
    }

    It 'blocks a group synced from on-premises AD' {
        $plan = Invoke-Plan -Current (Get-Range 1 2) -Desired (Get-Range 1 3) -Group @{ OnPremisesSynced = $true }
        $plan.Result | Should -Be 'Blocked'
        $plan.Write | Should -BeFalse
        $plan.Block | Should -BeLike '*on-premises AD*'
    }

    It 'blocks a role-assignable group' {
        (Invoke-Plan -Desired @('u1') -Group @{ IsAssignableToRole = $true }).Block | Should -BeLike '*role-assignable*'
    }

    It 'runs dry in a read-only installation, even when everything else would write' {
        $plan = Invoke-Plan -Current (Get-Range 1 5) -Desired (Get-Range 1 6) -AccessMode 'read-only'
        $plan.Result | Should -Be 'DryRun'
        $plan.DryRunReason | Should -Be 'readOnly'
        $plan.Write | Should -BeFalse
        ($plan.Adds) -join ',' | Should -Be 'u6'
    }

    It 'tells on a read-only dry run that a real run would be blocked by the change limit' {
        $plan = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 11 40) -AccessMode 'read-only'
        $plan.Result | Should -Be 'DryRun'
        $plan.Then.result | Should -Be 'Blocked'
        $plan.Then.message | Should -BeLike '*above the limit of 50 %*'
        $plan.Then.approvalKind | Should -Be 'changeLimit'
        $plan.PendingApproval | Should -BeNullOrEmpty
    }

    It 'tells on a dry run that a real run would be blocked by an empty result, or would write' {
        $empty = Invoke-Plan -Current (Get-Range 1 3) -Desired @() -Definition @{ DryRun = $true }
        $empty.DryRunReason | Should -Be 'definition'
        $empty.Then.result | Should -Be 'Blocked'
        $empty.Then.message | Should -BeLike '*matches nobody*'
        (Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 22) -AccessMode 'read-only').Then.result | Should -Be 'OK'
    }

    It 'tells on a read-only dry run that an adoption needs approval first' {
        $plan = Invoke-Plan -Current (Get-Range 1 3) -Desired (Get-Range 1 30) -Definition @{ TargetMode = 'adopt'; Adopted = $false } -AccessMode 'read-only'
        $plan.Then.result | Should -Be 'WaitingForApproval'
        $plan.Then.approvalKind | Should -Be 'adopt'
        $plan.Then.message | Should -BeLike '*approval first (27 changes*'
    }

    It 'has no Then outside dry runs' {
        (Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 22)).Then | Should -BeNullOrEmpty
    }

    It 'waits for approval on an adoption that is not approved yet' {
        $plan = Invoke-Plan -Current (Get-Range 1 10) -Desired (Get-Range 5 12) -Definition @{ TargetMode = 'adopt'; Adopted = $false }
        $plan.Result | Should -Be 'WaitingForApproval'
        $plan.DryRunReason | Should -Be 'adoption'
        $plan.PendingApproval.kind | Should -Be 'adopt'
        $plan.PendingApproval.diffHash | Should -BeExactly $plan.DiffHash
    }

    It 'writes an approved adoption whose diff still matches, even above the change limit' {
        $first = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 15 40) -Definition @{ TargetMode = 'adopt'; Adopted = $false }
        $approval = @{ kind = 'adopt'; diffHash = $first.DiffHash }
        $plan = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 15 40) -Definition @{ TargetMode = 'adopt'; Adopted = $true; Approval = $approval }
        $plan.Result | Should -Be 'OK'
        $plan.UseApprovalHash | Should -BeExactly $first.DiffHash
    }

    It 'applies the change limit again when an adopted group''s diff changed since approval' {
        $approval = @{ kind = 'adopt'; diffHash = 'sha256:' + ('0' * 64) }
        $plan = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 15 40) -Definition @{ TargetMode = 'adopt'; Adopted = $true; Approval = $approval }
        $plan.Result | Should -Be 'Blocked'
        $plan.PendingApproval.kind | Should -Be 'changeLimit'
    }

    It 'runs dry when the definition says so' {
        $plan = Invoke-Plan -Current (Get-Range 1 5) -Desired (Get-Range 1 6) -Definition @{ DryRun = $true }
        $plan.Result | Should -Be 'DryRun'
        $plan.DryRunReason | Should -Be 'definition'
    }

    It 'runs dry the first time when new groups start in dry run, but after the source check' {
        $plan = Invoke-Plan -Current @() -Desired (Get-Range 1 30) -NewGroupDryRun
        $plan.Result | Should -Be 'DryRun'
        $plan.DryRunReason | Should -Be 'newGroup'
        $plan.Write | Should -BeFalse
        $synced = Invoke-Plan -Current @() -Desired (Get-Range 1 3) -NewGroupDryRun -Group @{ OnPremisesSynced = $true }
        $synced.Result | Should -Be 'Blocked'
    }

    It 'blocks an empty result while the group has members' {
        $plan = Invoke-Plan -Current (Get-Range 1 3) -Desired @()
        $plan.Result | Should -Be 'Blocked'
        $plan.Block | Should -BeLike '*matches nobody*'
    }

    It 'allows an empty result with AllowEmpty, still subject to the change limit' {
        (Invoke-Plan -Current (Get-Range 1 3) -Desired @() -Definition @{ AllowEmpty = $true }).Result | Should -Be 'OK'
        (Invoke-Plan -Current (Get-Range 1 30) -Desired @() -Definition @{ AllowEmpty = $true }).Result | Should -Be 'Blocked'
    }

    It 'blocks more than 50 % changes from 10 changes up, with a pending approval' {
        $plan = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 31)
        $plan.Result | Should -Be 'Blocked'
        $plan.Percent | Should -Be 55
        $plan.PendingApproval.kind | Should -Be 'changeLimit'
        $plan.PendingApproval.adds | Should -Be 11
        $plan.Block | Should -BeLike '*above the limit of 50 %*'
    }

    It 'does not block below 10 changes even at a high percentage' {
        (Invoke-Plan -Current (Get-Range 1 2) -Desired (Get-Range 1 11)).Result | Should -Be 'OK'
    }

    It 'does not block exactly at the limit' {
        (Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 30)).Result | Should -Be 'OK'
    }

    It 'uses the definition''s own limit over the organisation default' {
        (Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 31) -Definition @{ ChangeLimitPercent = 80 }).Result | Should -Be 'OK'
        (Invoke-Plan -Current (Get-Range 1 40) -Desired (Get-Range 1 52) -Definition @{ ChangeLimitPercent = 20 }).Result | Should -Be 'Blocked'
    }

    It 'skips the change limit on the first fill of a group the engine created' {
        (Invoke-Plan -Current @() -Desired (Get-Range 1 200) -FirstFill).Result | Should -Be 'OK'
    }

    It 'writes a blocked change once after approval with the same diff hash' {
        $blocked = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 31)
        $approval = @{ kind = 'changeLimit'; diffHash = $blocked.DiffHash }
        $plan = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 31) -Definition @{ Approval = $approval }
        $plan.Result | Should -Be 'OK'
        $plan.UseApprovalHash | Should -BeExactly $blocked.DiffHash
    }

    It 'blocks again when the approved hash was already used' {
        $blocked = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 31)
        $approval = @{ kind = 'changeLimit'; diffHash = $blocked.DiffHash }
        $plan = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 31) -Definition @{ Approval = $approval } -Status @{ UsedApprovalHash = $blocked.DiffHash }
        $plan.Result | Should -Be 'Blocked'
    }

    It 'blocks a bigger change than the one approved' {
        $blocked = Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 31)
        $approval = @{ kind = 'changeLimit'; diffHash = $blocked.DiffHash }
        (Invoke-Plan -Current (Get-Range 1 20) -Desired (Get-Range 1 32) -Definition @{ Approval = $approval }).Result | Should -Be 'Blocked'
    }

    It 'reports a manual change as a warning and still writes' {
        $hash = InModuleScope DgEngine { Get-DgMemberSetHash -Ids @('u1', 'u2') }
        $plan = Invoke-Plan -Current @('u1', 'u2', 'u9') -Desired @('u1', 'u2') -Status @{ LastWrittenMembersHash = $hash }
        $plan.ManualChangeDetected | Should -BeTrue
        $plan.Result | Should -Be 'Warning'
        ($plan.Removes) -join ',' | Should -Be 'u9'
        $plan.Warnings[0] | Should -BeLike 'manual change detected*'
    }

    It 'passes desired-member warnings through as Warning' {
        $plan = Invoke-Plan -Current @('u1') -Desired @('u1') -Warnings @('always-include user x was not found')
        $plan.Result | Should -Be 'Warning'
    }
}

Describe 'Get-DgMemberDiff' {
    It 'adds and removes users only and leaves other members alone' {
        $diff = InModuleScope DgEngine {
            $desired = [System.Collections.Generic.HashSet[string]]::new([string[]]@('U1', 'u3'), [System.StringComparer]::OrdinalIgnoreCase)
            $current = @(
                [pscustomobject]@{ Id = 'u1'; IsUser = $true }
                [pscustomobject]@{ Id = 'u2'; IsUser = $true }
                [pscustomobject]@{ Id = 'g9'; IsUser = $false }
            )
            Get-DgMemberDiff -DesiredIds $desired -CurrentMembers $current
        }
        ($diff.Adds) -join ',' | Should -Be 'u3'
        ($diff.Removes) -join ',' | Should -Be 'u2'
        $diff.NonUserMembers | Should -Be 1
        $diff.CurrentUserCount | Should -Be 2
    }
}

Describe 'Hashes' {
    It 'ignores order and case in member set hashes' {
        InModuleScope DgEngine {
            Get-DgMemberSetHash -Ids @('B', 'a') | Should -BeExactly (Get-DgMemberSetHash -Ids @('a', 'b'))
            Get-DgMemberSetHash -Ids @('a') | Should -Not -Be (Get-DgMemberSetHash -Ids @('a', 'b'))
            Get-DgMemberSetHash -Ids @() | Should -BeLike 'sha256:*'
        }
    }

    It 'tells adds from removes in diff hashes' {
        InModuleScope DgEngine {
            Get-DgDiffHash -Adds @('a') -Removes @() | Should -Not -Be (Get-DgDiffHash -Adds @() -Removes @('a'))
        }
    }
}

Describe 'Test-DgSnapshotHealth' {
    It 'accepts <Count> users after <Previous>' -ForEach @(
        @{ Count = 100; Previous = 100 }
        @{ Count = 80; Previous = 100 }
        @{ Count = 5; Previous = 19 }
        @{ Count = 50; Previous = $null }
    ) {
        InModuleScope DgEngine -Parameters @{ Count = $Count; Previous = $Previous } {
            Test-DgSnapshotHealth -UserCount $Count -PreviousUserCount $Previous | Should -BeNullOrEmpty
        }
    }

    It 'refuses <Count> users after <Previous>' -ForEach @(
        @{ Count = 0; Previous = $null }
        @{ Count = 79; Previous = 100 }
    ) {
        InModuleScope DgEngine -Parameters @{ Count = $Count; Previous = $Previous } {
            Test-DgSnapshotHealth -UserCount $Count -PreviousUserCount $Previous | Should -Not -BeNullOrEmpty
        }
    }
}
