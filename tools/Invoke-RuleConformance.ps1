#Requires -Version 7.4
<#
.SYNOPSIS
    Runs the rule conformance suite (tests/rules/*.json) against DgEngine.
.DESCRIPTION
    Each file holds cases. A valid case states the expected syntax tree as Format-DgRuleAst
    renders it; an invalid case states the 0-based error position and a substring of the
    message; an evaluation case (in a file with users) lists the users the rule must match. Runs without Pester, so it works anywhere PowerShell 7.4 runs; the Pester test
    tests/DgEngine/Rules/Conformance.Tests.ps1 uses the same cases.
.PARAMETER Path
    Folder with the case files. Defaults to tests/rules.
.PARAMETER PassThru
    Return one result object per case instead of printing a summary.
.EXAMPLE
    ./tools/Invoke-RuleConformance.ps1
#>
[CmdletBinding()]
param(
    [string] $Path = (Join-Path -Path $PSScriptRoot -ChildPath '../tests/rules'),

    [switch] $PassThru
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../src/DgEngine/DgEngine.psd1'
$module = Import-Module -Name $modulePath -Force -PassThru

$results = foreach ($file in Get-ChildItem -Path $Path -Filter '*.json' -File | Sort-Object -Property Name) {
    $suite = Get-Content -Path $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    # Evaluation suites carry users (Graph field names), group members and a fixed "now".
    $users = @{}
    $context = $null
    if ($suite.PSObject.Properties['users']) {
        $userTable = Get-Content -Path $file.FullName -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        foreach ($key in $userTable.users.Keys) { $users[$key] = $userTable.users[$key] }
        $groupMembers = @{}
        foreach ($groupId in $userTable.groups.Keys) {
            $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($userKey in $userTable.groups[$groupId]) { [void]$set.Add($users[$userKey].id) }
            $groupMembers[$groupId] = $set
        }
        $context = @{ Now = [DateTimeOffset]::Parse($suite.now, [cultureinfo]::InvariantCulture); GroupMembers = $groupMembers }
    }

    foreach ($case in $suite.cases) {
        $check = Test-DgRule -Rule $case.rule
        $problem = $null
        if ($case.PSObject.Properties['matches']) {
            if (-not $check.Valid) {
                $problem = "rule is not valid: $($check.Errors[0].Message)"
            } else {
                $actualKeys = & $module {
                    param($ast, $users, $context)
                    $compiled = ConvertTo-DgCompiledRule -Node $ast
                    foreach ($key in $users.Keys) {
                        if (Test-DgRuleMatch -Node $compiled -User $users[$key] -Context $context) { $key }
                    }
                } $check.Ast $users $context
                $actual = (@($actualKeys) | Sort-Object) -join ', '
                $expected = (@($case.matches) | Sort-Object) -join ', '
                if ($actual -cne $expected) {
                    $problem = "matches differ`n      expected: $expected`n      actual:   $actual"
                }
            }
        } elseif ($case.valid) {
            if (-not $check.Valid) {
                $problem = "expected valid, got error at $($check.Errors[0].Position): $($check.Errors[0].Message)"
            } else {
                $tree = & $module { param($ast) Format-DgRuleAst -Node $ast } $check.Ast
                if ($tree -cne $case.tree) {
                    $problem = "tree differs`n      expected: $($case.tree)`n      actual:   $tree"
                }
            }
        } else {
            if ($check.Valid) {
                $problem = 'expected an error, but the rule was accepted'
            } else {
                $actual = $check.Errors[0]
                if ($actual.Position -ne $case.error.position) {
                    $problem = "error position $($actual.Position), expected $($case.error.position) ($($actual.Message))"
                } elseif (-not $actual.Message.Contains([string]$case.error.message)) {
                    $problem = "error message '$($actual.Message)' doesn't contain '$($case.error.message)'"
                }
            }
        }
        [pscustomobject]@{
            File    = $file.Name
            Id      = $case.id
            Rule    = $case.rule
            Passed  = $null -eq $problem
            Problem = $problem
        }
    }
}

if ($PassThru) {
    return $results
}

$failed = @($results | Where-Object { -not $_.Passed })
foreach ($result in $failed) {
    Write-Information -MessageData "FAIL $($result.File) $($result.Id)`n      rule: $($result.Rule)`n      $($result.Problem)" -InformationAction Continue
}
Write-Information -MessageData "$(@($results).Count - $failed.Count) of $(@($results).Count) cases passed." -InformationAction Continue
if ($failed.Count) {
    exit 1
}
