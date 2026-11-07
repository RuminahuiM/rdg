#Requires -Version 7.4
# Runs every case in tests/rules/*.json as one Pester test. Same checks as
# tools/Invoke-RuleConformance.ps1, but evaluated inside the test so code coverage counts them.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester passes $cases from BeforeDiscovery to -ForEach.')]
param()

BeforeDiscovery {
    $casesPath = Join-Path -Path $PSScriptRoot -ChildPath '../../rules'
    $cases = foreach ($file in Get-ChildItem -Path $casesPath -Filter '*.json' -File | Sort-Object -Property Name) {
        $suite = Get-Content -Path $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json
        foreach ($case in $suite.cases) {
            $isEvaluation = [bool]$case.PSObject.Properties['matches']
            $valid = $isEvaluation -or [bool]$case.valid
            @{
                File          = $file.Name
                FullName      = $file.FullName
                Id            = $case.id
                Rule          = $case.rule
                Valid         = $valid
                Tree          = if ($valid -and -not $isEvaluation) { $case.tree } else { $null }
                IsEvaluation  = $isEvaluation
                # Comma keeps an empty list a list; a bare empty array would become $null.
                ExpectedUsers = if ($isEvaluation) { , [string[]]@($case.matches) } else { $null }
                ErrorPosition = if ($valid) { $null } else { [int]$case.error.position }
                ErrorMessage  = if ($valid) { $null } else { [string]$case.error.message }
            }
        }
    }
}

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
}

Describe 'Rule conformance suite' {
    It '<File> <Id>' -ForEach $cases {
        $check = Test-DgRule -Rule $Rule
        # Named ExpectedUsers, not Matches: $Matches is an automatic variable.
        if ($IsEvaluation) {
            $check.Errors | Should -HaveCount 0 -Because "rule: $Rule"
            $suite = Get-Content -Path $FullName -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
            $actual = InModuleScope DgEngine -Parameters @{ Ast = $check.Ast; Suite = $suite } {
                $groupMembers = @{}
                foreach ($groupId in $Suite.groups.Keys) {
                    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($key in $Suite.groups[$groupId]) { [void]$set.Add($Suite.users[$key].id) }
                    $groupMembers[$groupId] = $set
                }
                $context = @{ Now = [DateTimeOffset]::Parse($Suite.now, [cultureinfo]::InvariantCulture); GroupMembers = $groupMembers }
                $compiled = ConvertTo-DgCompiledRule -Node $Ast
                foreach ($key in $Suite.users.Keys) {
                    if (Test-DgRuleMatch -Node $compiled -User $Suite.users[$key] -Context $context) { $key }
                }
            }
            ((@($actual) | Sort-Object) -join ', ') | Should -BeExactly ((@($ExpectedUsers) | Sort-Object) -join ', ')
        } elseif ($Valid) {
            $check.Errors | Should -HaveCount 0 -Because "rule: $Rule"
            $actualTree = InModuleScope DgEngine -Parameters @{ Ast = $check.Ast } { Format-DgRuleAst -Node $Ast }
            $actualTree | Should -BeExactly $Tree
        } else {
            $check.Valid | Should -BeFalse -Because "rule: $Rule"
            $check.Errors[0].Position | Should -Be $ErrorPosition -Because $check.Errors[0].Message
            $check.Errors[0].Message | Should -BeLike "*$([WildcardPattern]::Escape($ErrorMessage))*"
        }
    }
}
