#Requires -Version 7.4

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
}

Describe 'Select-DgImplicitFilter' {
    BeforeAll {
        $script:users = @(
            @{ id = '1'; accountEnabled = $true; userType = 'Member' }
            @{ id = '2'; accountEnabled = $false; userType = 'Member' }
            @{ id = '3'; accountEnabled = $true; userType = 'Guest' }
            @{ id = '4'; accountEnabled = $false; userType = 'Guest' }
        )
    }

    It 'drops disabled accounts and guests by default, counting each user once' {
        $result = InModuleScope DgEngine -Parameters @{ Users = $users } { Select-DgImplicitFilter -Users $Users }
        ($result.Kept.id) -join ',' | Should -Be '1'
        $result.Counts.Disabled | Should -Be 2
        $result.Counts.Guests | Should -Be 1
        ($result.Excluded.Reason) -join ',' | Should -Be 'disabled,guest,disabled'
    }

    It 'keeps disabled accounts with -IncludeDisabled' {
        $result = InModuleScope DgEngine -Parameters @{ Users = $users } { Select-DgImplicitFilter -Users $Users -IncludeDisabled }
        ($result.Kept.id) -join ',' | Should -Be '1,2'
        $result.Counts.Guests | Should -Be 2
    }

    It 'keeps everyone with both switches' {
        $result = InModuleScope DgEngine -Parameters @{ Users = $users } { Select-DgImplicitFilter -Users $Users -IncludeDisabled -IncludeGuests }
        $result.Kept | Should -HaveCount 4
        $result.Excluded | Should -HaveCount 0
    }

    It 'handles an empty result' {
        $result = InModuleScope DgEngine { Select-DgImplicitFilter -Users @() }
        $result.Kept | Should -HaveCount 0
    }
}

Describe 'Test-DgRuleMatch safety' {
    It 'stops a regular expression that runs longer than 100 ms' {
        InModuleScope DgEngine {
            $compiled = ConvertTo-DgCompiledRule -Node (Test-DgRule -Rule 'user.displayName -match "^(a+)+$"').Ast
            $user = @{ id = 'x'; displayName = ('a' * 40) + '!' }
            { Test-DgRuleMatch -Node $compiled -User $user -Context @{ Now = [DateTimeOffset]::UtcNow; GroupMembers = @{} } } |
                Should -Throw -ExpectedMessage '*took longer than 100 ms*'
        }
    }

    It 'refuses to guess when a memberOf group was not loaded' {
        InModuleScope DgEngine {
            $rule = "user.memberOf -any (group.objectId -in ['9a9a9a9a-0000-4000-8000-000000000001'])"
            $compiled = ConvertTo-DgCompiledRule -Node (Test-DgRule -Rule $rule).Ast
            { Test-DgRuleMatch -Node $compiled -User @{ id = 'x' } -Context @{ Now = [DateTimeOffset]::UtcNow; GroupMembers = @{} } } |
                Should -Throw -ExpectedMessage '*were not loaded*'
        }
    }
}
