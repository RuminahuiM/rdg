function Test-DgRule {
    <#
    .SYNOPSIS
        Checks rule text and returns whether it is valid, with every error and its position.
    .DESCRIPTION
        Used by the API (POST /api/rules/validate) while the user types, and by the engine before
        a run. Never throws for a bad rule: errors are returned in Errors with 0-based Position,
        1-based Line and Column, Length to underline and a Message.

        Syntax errors stop at the first one. When the syntax is fine, every problem with
        properties, operator/type combinations, values and regular expressions is returned,
        sorted by position. Ast is returned even then, for tooling; only use it when Valid.
    .PARAMETER Rule
        The rule text, in Entra dynamic membership syntax.
    .PARAMETER MaxLength
        Maximum rule length in characters (default 10,000).
    .EXAMPLE
        Test-DgRule -Rule 'user.department -eq "Sales"'
    .EXAMPLE
        (Test-DgRule -Rule 'user.department -eq').Errors[0].Message   # expected a value after -eq
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $Rule,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $MaxLength = 10000
    )

    process {
        $ast = $null
        $errors = @()
        try {
            $ast = ConvertTo-DgRuleAst -Rule $Rule -MaxLength $MaxLength
        } catch [System.FormatException] {
            if (-not $_.Exception.Data.Contains('DgRuleError')) {
                throw
            }
            $errors = @($_.Exception.Data['DgRuleError'])
        }

        if ($ast) {
            $errors = @(Get-DgRuleSemanticError -Rule $Rule -Ast $ast)
        }
        $references = if ($ast) { Get-DgRuleReference -Ast $ast } else { $null }

        [pscustomobject]@{
            PSTypeName           = 'Dg.RuleCheck'
            Valid                = $errors.Count -eq 0
            Errors               = $errors
            Ast                  = $ast
            ReferencedProperties = if ($references) { $references.Properties } else { [string[]]@() }
            ReferencedGroupIds   = if ($references) { $references.GroupIds } else { [string[]]@() }
        }
    }
}
