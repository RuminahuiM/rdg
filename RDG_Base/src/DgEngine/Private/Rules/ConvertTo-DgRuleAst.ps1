function ConvertTo-DgRuleAst {
    <#
    .SYNOPSIS
        Parses rule text into a syntax tree.
    .DESCRIPTION
        Recursive-descent parser for the Entra dynamic membership rule grammar:

            rule           = directReports | orExpr
            orExpr         = andExpr { "-or" andExpr }
            andExpr        = notExpr { "-and" notExpr }
            notExpr        = "-not" notExpr | primary
            primary        = "(" orExpr ")" | collectionTest | comparison
            comparison     = property operator value
            collectionTest = property ("-any" | "-all") "(" orExpr ")"   -- items: _, assignedPlan.x, group.x
            value          = string | number | true | false | null | list | dateValue
            list           = "[" scalar { "," scalar } "]"
            dateValue      = isoDateTime | "system.now" [ ("-plus" | "-minus") isoDuration ]
            directReports  = "Direct Reports for" string

        Stops at the first error and throws it (see Invoke-DgRuleError). Checks that need the
        property types (unknown property, operator not allowed for a type, regex validity) are
        done afterwards by the validator.

        Nodes are [pscustomobject] with PSTypeName 'Dg.RuleNode' and a Kind: Or, And, Not,
        Comparison, Collection, DirectReports. Every node has Position and Length.

        Nesting (parentheses and -not) is limited to 100 levels, so a hostile rule can't exhaust
        the call stack of the host (Function App, Automation sandbox).
    .EXAMPLE
        ConvertTo-DgRuleAst -Rule '(user.department -eq "Sales") -or (user.city -eq "Bern")'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Rule,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $MaxLength = 10000
    )

    $state = @{ Rule = $Rule; Tokens = @(); Index = 0; InCollection = $false; Depth = 0 }

    if ($Rule.Length -gt $MaxLength) {
        Invoke-DgRuleError -State $state -Position $MaxLength -Length ($Rule.Length - $MaxLength) -Message "the rule is longer than $MaxLength characters"
    }
    if ([string]::IsNullOrWhiteSpace($Rule)) {
        Invoke-DgRuleError -State $state -Position 0 -Length 0 -Message 'the rule is empty'
    }

    $state.Tokens = ConvertTo-DgRuleToken -State $state

    $directReports = Read-DgRuleDirectReport -State $state
    if ($directReports) {
        return $directReports
    }

    $ast = Read-DgRuleOrExpression -State $state
    $token = $state.Tokens[$state.Index]
    if ($token.Kind -ne 'End') {
        if ($token.Kind -eq 'RParen') {
            Invoke-DgRuleError -State $state -Position $token.Position -Message 'this ) has no matching ('
        }
        Invoke-DgRuleError -State $state -Position $token.Position -Length $token.Length `
            -Message "unexpected $($token.Text) after a complete condition; is -and or -or missing?"
    }
    $ast
}
