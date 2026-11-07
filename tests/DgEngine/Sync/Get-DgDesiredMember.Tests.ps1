#Requires -Version 7.4

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
    $script:users = @(
        @{ id = 'u1'; city = 'Bern'; accountEnabled = $true; userType = 'Member'; userPrincipalName = 'u1@contoso.org' }
        @{ id = 'u2'; city = 'Bern'; accountEnabled = $false; userType = 'Member'; userPrincipalName = 'u2@contoso.org' }
        @{ id = 'u3'; city = 'Basel'; accountEnabled = $true; userType = 'Guest'; userPrincipalName = 'u3@contoso.org' }
        @{ id = 'u4'; city = 'Basel'; accountEnabled = $true; userType = 'Member'; userPrincipalName = 'u4@contoso.org' }
    )
    function Get-Desired {
        param([hashtable] $Definition)
        InModuleScope DgEngine -Parameters @{ Def = $Definition; U = $users } {
            $compiled = ConvertTo-DgCompiledRule -Node (Test-DgRule -Rule 'user.city -eq "Bern"').Ast
            Get-DgDesiredMember -Compiled $compiled -Definition $Def -Users $U -Context @{ Now = [DateTimeOffset]::UtcNow; GroupMembers = @{} }
        }
    }
}

Describe 'Get-DgDesiredMember' {
    It 'applies the implicit filters to the rule result' {
        ((Get-Desired -Definition @{}).Members.id) -join ',' | Should -Be 'u1'
    }

    It 'adds always-include users, bypassing the filters' {
        $desired = Get-Desired -Definition @{ IncludeUserIds = @('u3', 'u4') }
        ($desired.Members.id) -join ',' | Should -Be 'u1,u3,u4'
        $desired.MemberIds.Contains('U3') | Should -BeTrue
    }

    It 'lets always-exclude win over the rule and over includes' {
        $desired = Get-Desired -Definition @{ IncludeUserIds = @('u4'); ExcludeUserIds = @('u1', 'u4') }
        $desired.Members | Should -HaveCount 0
        $desired.MemberIds.Count | Should -Be 0
    }

    It 'warns about an always-include user who does not exist' {
        $desired = Get-Desired -Definition @{ IncludeUserIds = @('ghost') }
        ($desired.Members.id) -join ',' | Should -Be 'u1'
        $desired.Warnings[0] | Should -Be 'always-include user ghost was not found'
    }
}

Describe 'Get-DgCompareResult' {
    It 'lists who is only in RDG and only in the compare group, with UPNs' {
        $result = InModuleScope DgEngine -Parameters @{ U = $users } {
            $desired = [System.Collections.Generic.HashSet[string]]::new([string[]]@('u1', 'u4'), [System.StringComparer]::OrdinalIgnoreCase)
            Get-DgCompareResult -GroupId 'AAAA' -DesiredIds $desired -CompareIds @('u4', 'u3') -Users $U
        }
        $result.groupId | Should -Be 'aaaa'
        $result.onlyInRdgCount | Should -Be 1
        $result.onlyInRdg[0].upn | Should -Be 'u1@contoso.org'
        $result.onlyInCompareCount | Should -Be 1
        $result.onlyInCompare[0].id | Should -Be 'u3'
    }
}
