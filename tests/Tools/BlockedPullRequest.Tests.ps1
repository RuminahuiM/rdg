#Requires -Version 7.4
# Proof for the branch ruleset (CI-5): this pull request fails on purpose and must not be mergeable.
# Never merge this file.

Describe 'Branch ruleset proof' {
    It 'fails on purpose' {
        1 | Should -Be 2
    }
}
