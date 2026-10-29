#Requires -Version 7.4
# The web app's property list (src/Web/src/rules/properties.json) must match the engine.

Describe 'Export-RuleProperties' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '../../..'
        $script:tool = Join-Path -Path $root -ChildPath 'tools/Export-RuleProperties.ps1'
        $script:file = Join-Path -Path $root -ChildPath 'src/Web/src/rules/properties.json'
        $script:module = Import-Module -Name (Join-Path -Path $root -ChildPath 'src/DgEngine/DgEngine.psd1') -Force -PassThru
    }

    It 'the committed file is current (run tools/Export-RuleProperties.ps1 if this fails)' {
        $expected = & $script:tool -PassThru
        $actual = (Get-Content -Path $script:file -Raw -Encoding utf8) -replace "`r`n", "`n"
        $actual.TrimEnd("`n") | Should -Be $expected
    }

    It 'lists every property once with a known type' {
        $list = (& $script:tool -PassThru | ConvertFrom-Json).properties
        $list.Count | Should -Be (& $script:module { (Get-DgPropertyMap).Count })
        @($list.name | Sort-Object -Unique).Count | Should -Be $list.Count
        foreach ($p in $list) {
            $p.type | Should -BeIn @('String', 'Boolean', 'Date', 'StringCollection', 'PlanCollection', 'GroupCollection')
        }
    }
}
