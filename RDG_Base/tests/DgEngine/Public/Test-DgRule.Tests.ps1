#Requires -Version 7.4

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
}

Describe 'Test-DgRule' {
    It 'returns Valid, no errors and the syntax tree for a valid rule' {
        $check = Test-DgRule -Rule 'user.department -eq "Sales"'
        $check.Valid | Should -BeTrue
        $check.Errors | Should -HaveCount 0
        $check.Ast.Kind | Should -Be 'Comparison'
    }

    It 'returns the first error with position, line, column, length and message' {
        $check = Test-DgRule -Rule '(user.department -eq )'
        $check.Valid | Should -BeFalse
        $check.Errors | Should -HaveCount 1
        $check.Errors[0].Position | Should -Be 21
        $check.Errors[0].Line | Should -Be 1
        $check.Errors[0].Column | Should -Be 22
        $check.Errors[0].Length | Should -Be 1
        $check.Errors[0].Message | Should -BeLike 'expected a value after -eq*'
        $check.Ast | Should -BeNullOrEmpty
    }

    It 'lists referenced properties lower-case and unique' {
        $check = Test-DgRule -Rule 'user.City -eq "Bern" -or user.city -eq "Basel" -or user.Department -ne null'
        $check.Valid | Should -BeTrue
        ($check.ReferencedProperties) -join '|' | Should -Be (@('city', 'department') -join '|')
    }

    It 'lists group IDs referenced through memberOf' {
        $id1 = '7c1e2d3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f'
        $id2 = '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d'
        $check = Test-DgRule -Rule "user.memberOf -any (group.objectId -in ['$id1','$id2'])"
        ($check.ReferencedGroupIds) -join '|' | Should -Be (@($id2, $id1) -join '|')
    }

    It 'enforces the maximum length' {
        $check = Test-DgRule -Rule ('user.city -eq "' + ('x' * 50) + '"') -MaxLength 20
        $check.Valid | Should -BeFalse
        $check.Errors[0].Message | Should -Be 'the rule is longer than 20 characters'
    }

    It 'accepts rules from the pipeline' {
        $results = 'user.city -eq "Bern"', 'user.city -eq' | Test-DgRule
        ($results.Valid) -join '|' | Should -Be (@($true, $false) -join '|')
    }

    It 'returns a suggestion for a likely typo in an operator' {
        (Test-DgRule -Rule 'user.city -equals "Bern"').Errors[0].Suggestion | Should -Be '-eq'
    }

    It 'returns every validation error, sorted by position' {
        $check = Test-DgRule -Rule 'user.colour -eq "x" -and user.department -ge "A" -and user.accountEnabled -eq "maybe"'
        $check.Valid | Should -BeFalse
        $check.Errors | Should -HaveCount 3
        ($check.Errors.Position) -join ',' | Should -Be '0,25,78'
    }

    It 'suggests the closest property name' {
        (Test-DgRule -Rule 'user.extensionAtribute3 -eq "x"').Errors[0].Suggestion | Should -Be 'extensionAttribute3'
    }
}
