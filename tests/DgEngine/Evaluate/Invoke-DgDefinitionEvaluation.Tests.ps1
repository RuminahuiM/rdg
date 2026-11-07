#Requires -Version 7.4

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force

    # Invented users: u1..u4 in Bern/Basel, u5 disabled in Bern.
    $script:users = @(
        @{ id = 'u1'; city = 'Bern'; department = 'Sales'; accountEnabled = $true; userType = 'Member' }
        @{ id = 'u2'; city = 'Bern'; department = 'IT'; accountEnabled = $true; userType = 'Member' }
        @{ id = 'u3'; city = 'Basel'; department = 'Sales'; accountEnabled = $true; userType = 'Member' }
        @{ id = 'u4'; city = 'Basel'; department = 'HR'; accountEnabled = $true; userType = 'Member' }
        @{ id = 'u5'; city = 'Bern'; department = 'Sales'; accountEnabled = $false; userType = 'Member' }
    )
    $script:gA = 'aaaaaaaa-0000-4000-8000-00000000000a'
    $script:gB = 'bbbbbbbb-0000-4000-8000-00000000000b'
    $script:gC = 'cccccccc-0000-4000-8000-00000000000c'
    $script:gX = 'eeeeeeee-0000-4000-8000-00000000000e'   # not managed by RDG
    $script:now = [DateTimeOffset]::Parse('2026-10-11T12:00:00Z')

    function Get-TestDefinition {
        param([string] $Id, [string] $GroupId, [string] $Rule)
        @{ Id = $Id; Name = "Def $Id"; GroupId = $GroupId; Rule = $Rule; IncludeDisabled = $false; IncludeGuests = $false }
    }
    function Get-MemberIdList { param($Result) (@($Result.Desired.Members | ForEach-Object { $_.id }) | Sort-Object) -join ',' }

    # Provider for groups RDG doesn't manage: records every call.
    $script:providerCalls = [System.Collections.Generic.List[string]]::new()
    $script:provider = {
        param([string] $GroupId, [bool] $Transitive)
        $script:providerCalls.Add("$GroupId|$Transitive")
        if ($GroupId -eq $script:gX) {
            $ids = if ($Transitive) { @('u3', 'u4') } else { @('u3') }
            return [pscustomobject]@{ Found = $true; UserIds = $ids }
        }
        [pscustomobject]@{ Found = $false; UserIds = @() }
    }
}

Describe 'Invoke-DgDefinitionEvaluation' {
    BeforeEach {
        $script:providerCalls.Clear()
    }

    It 'evaluates a chain dependencies first and uses the referenced definition''s fresh result' {
        # A = members of B in Sales; B = members of C; C = everyone in Bern (u5 disabled, filtered out).
        $definitions = @(
            Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$gB']) -and user.department -eq ""Sales"""
            Get-TestDefinition -Id 'B' -GroupId $gB -Rule "user.memberOf -any (group.objectId -in ['$gC'])"
            Get-TestDefinition -Id 'C' -GroupId $gC -Rule 'user.city -eq "Bern"'
        )
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        ($results.Status) -join ',' | Should -Be 'OK,OK,OK'
        Get-MemberIdList ($results | Where-Object DefinitionId -EQ 'C') | Should -Be 'u1,u2'
        Get-MemberIdList ($results | Where-Object DefinitionId -EQ 'B') | Should -Be 'u1,u2'
        Get-MemberIdList ($results | Where-Object DefinitionId -EQ 'A') | Should -Be 'u1'
        $providerCalls | Should -HaveCount 0
    }

    It 'reads groups RDG does not manage through the provider, once, with nested members by default' {
        $definitions = @(
            Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$gX'])"
            Get-TestDefinition -Id 'B' -GroupId $gB -Rule "user.memberOf -any (group.objectId -in ['$gX']) -and user.department -eq ""HR"""
        )
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        Get-MemberIdList ($results | Where-Object DefinitionId -EQ 'A') | Should -Be 'u3,u4'
        Get-MemberIdList ($results | Where-Object DefinitionId -EQ 'B') | Should -Be 'u4'
        ($providerCalls) -join ';' | Should -Be "$gX|True"
    }

    It 'reads direct members only when the nested members setting is off' {
        $definitions = @(Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$gX'])")
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P -NestedMembers $false
        }
        Get-MemberIdList $results | Should -Be 'u3'
        ($providerCalls) -join ';' | Should -Be "$gX|False"
    }

    It 'reports a missing memberOf group on the definition that uses it only' {
        $missing = '99999999-0000-4000-8000-000000000099'
        $definitions = @(
            Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$missing'])"
            Get-TestDefinition -Id 'B' -GroupId $gB -Rule 'user.city -eq "Basel"'
        )
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        ($results | Where-Object DefinitionId -EQ 'A').Status | Should -Be 'Error'
        ($results | Where-Object DefinitionId -EQ 'A').Error | Should -BeLike "*$missing doesn't exist*"
        ($results | Where-Object DefinitionId -EQ 'B').Status | Should -Be 'OK'
    }

    It 'reports a provider failure on the definition instead of stopping' {
        $definitions = @(Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$gX'])")
        $broken = { param([string] $GroupId, [bool] $Transitive) throw "Graph throttled reading $GroupId (nested: $Transitive)" }
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $broken } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        $results.Status | Should -Be 'Error'
        $results.Error | Should -BeLike '*Graph throttled*'
    }

    It 'detects a cycle, names it, and fails definitions that depend on it' {
        $definitions = @(
            Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$gB'])"
            Get-TestDefinition -Id 'B' -GroupId $gB -Rule "user.memberOf -any (group.objectId -in ['$gA'])"
            Get-TestDefinition -Id 'C' -GroupId $gC -Rule "user.memberOf -any (group.objectId -in ['$gA'])"
            Get-TestDefinition -Id 'D' -GroupId $null -Rule 'user.city -eq "Bern"'
        )
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        ($results | Where-Object DefinitionId -EQ 'A').Error | Should -Be 'memberOf cycle: Def A -> Def B -> Def A'
        ($results | Where-Object DefinitionId -EQ 'B').Error | Should -BeLike 'memberOf cycle:*'
        ($results | Where-Object DefinitionId -EQ 'C').Error | Should -BeLike 'depends on Def A, which failed: memberOf cycle*'
        ($results | Where-Object DefinitionId -EQ 'D').Status | Should -Be 'OK'
    }

    It 'treats a rule that uses its own group as a cycle' {
        $definitions = @(Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$gA'])")
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        $results.Error | Should -Be 'memberOf cycle: Def A -> Def A'
    }

    It 'fails a definition with an invalid rule and the definitions that depend on it' {
        $definitions = @(
            Get-TestDefinition -Id 'A' -GroupId $gA -Rule 'user.colour -eq "blue"'
            Get-TestDefinition -Id 'B' -GroupId $gB -Rule "user.memberOf -any (group.objectId -in ['$gA'])"
        )
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        ($results | Where-Object DefinitionId -EQ 'A').Error | Should -BeLike 'the rule is not valid: unknown property user.colour*'
        ($results | Where-Object DefinitionId -EQ 'B').Error | Should -BeLike 'depends on Def A, which failed*'
    }

    It 'evaluates the targets plus their dependencies only' {
        $definitions = @(
            Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$gB'])"
            Get-TestDefinition -Id 'B' -GroupId $gB -Rule 'user.city -eq "Bern"'
            Get-TestDefinition -Id 'C' -GroupId $gC -Rule 'user.city -eq "Basel"'
        )
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -TargetIds @('A') -Users $U -Now $N -GroupMemberProvider $P
        }
        ($results.DefinitionId) -join ',' | Should -Be 'A,B'
        ($results.IsTarget) -join ',' | Should -Be 'True,False'
    }

    It 'fails both definitions when two are linked to the same group' {
        $definitions = @(
            Get-TestDefinition -Id 'A' -GroupId $gA -Rule 'user.city -eq "Bern"'
            Get-TestDefinition -Id 'B' -GroupId $gA.ToUpperInvariant() -Rule 'user.city -eq "Basel"'
        )
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        ($results.Status) -join ',' | Should -Be 'Error,Error'
        $results[0].Error | Should -BeLike '*linked to more than one definition*'
    }

    It 'applies the referenced definition''s filters: a disabled user excluded there is not a member here' {
        $definitions = @(
            Get-TestDefinition -Id 'A' -GroupId $gA -Rule "user.memberOf -any (group.objectId -in ['$gB'])"
            (Get-TestDefinition -Id 'B' -GroupId $gB -Rule 'user.department -eq "Sales"')
        )
        $definitions[0].IncludeDisabled = $true
        $results = InModuleScope DgEngine -Parameters @{ D = $definitions; U = $users; N = $now; P = $provider } {
            Invoke-DgDefinitionEvaluation -Definitions $D -Users $U -Now $N -GroupMemberProvider $P
        }
        Get-MemberIdList ($results | Where-Object DefinitionId -EQ 'B') | Should -Be 'u1,u3'
        Get-MemberIdList ($results | Where-Object DefinitionId -EQ 'A') | Should -Be 'u1,u3'
    }
}

Describe 'Get-DgDefinitionOrder' {
    It 'orders a diamond dependencies first and keeps input order for ties' {
        $order = InModuleScope DgEngine {
            Get-DgDefinitionOrder -Ids @('top', 'left', 'right', 'bottom') -Dependencies @{
                top = @('left', 'right'); left = @('bottom'); right = @('bottom'); bottom = @()
            }
        }
        ($order.Order) -join ',' | Should -Be 'bottom,left,right,top'
        $order.Cycles.Count | Should -Be 0
    }

    It 'finds a three-step cycle and leaves the dependent out of the order' {
        $order = InModuleScope DgEngine {
            Get-DgDefinitionOrder -Ids @('a', 'b', 'c', 'd', 'e') -Dependencies @{
                a = @('b'); b = @('c'); c = @('a'); d = @('a'); e = @()
            }
        }
        ($order.Order) -join ',' | Should -Be 'e'
        ($order.Cycles['a']) -join '>' | Should -Be 'a>b>c>a'
        $order.Cycles.ContainsKey('d') | Should -BeFalse
    }
}
