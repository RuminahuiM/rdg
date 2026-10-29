#Requires -Version 7.4
# The engine's verbose log: only its own lines, and only when the setting is on.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
}

Describe 'Write-DgVerbose' {
    It 'writes nothing while verbose logging is off' {
        InModuleScope DgEngine {
            Set-DgVerboseLogging -Enabled $false
            @(Write-DgVerbose -Message 'hidden' 4>&1) | Should -HaveCount 0
        }
    }

    It 'writes its own lines when on, without turning on $VerbosePreference for other modules' {
        InModuleScope DgEngine {
            Set-DgVerboseLogging -Enabled $true
            try {
                $lines = @(Write-DgVerbose -Message 'shown' 4>&1)
                $lines | Should -HaveCount 1
                $lines[0].Message | Should -Be 'shown'
                $VerbosePreference | Should -Be 'SilentlyContinue'
            } finally {
                Set-DgVerboseLogging -Enabled $false
            }
        }
    }
}

Describe 'Format-DgOutcomeLine' {
    It 'names result, counts and what a real run would do, without user names' {
        InModuleScope DgEngine {
            $outcome = [pscustomobject]@{
                Name = 'Finance'; Result = 'DryRun'; DryRunReason = 'readOnly'; MemberCount = 24; Added = 24; Removed = 3; Skipped = 0; DurationMs = 812
                Then = [ordered]@{ result = 'Blocked'; message = '27 changes are 900 % of 3 members'; approvalKind = 'changeLimit' }; Error = $null
            }
            Format-DgOutcomeLine -Outcome $outcome | Should -Be 'Finance: DryRun (readOnly), 24 members, +24/-3, 0 skipped, 812 ms; then Blocked: 27 changes are 900 % of 3 members'
        }
    }
}
