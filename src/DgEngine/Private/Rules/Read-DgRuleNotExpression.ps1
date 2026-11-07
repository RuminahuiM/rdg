function Read-DgRuleNotExpression {
    <#
    .SYNOPSIS
        notExpr = "-not" notExpr | primary
    .DESCRIPTION
        As in Entra, -not directly on a comparison with null is an error: use -ne null instead.
    .EXAMPLE
        Read-DgRuleNotExpression -State $state
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $token = $State.Tokens[$State.Index]
    if ($token.Kind -eq 'Word' -and (Get-DgRuleOperatorName -Word $token.Value) -eq 'not') {
        Enter-DgRuleNesting -State $State -Token $token
        $State.Index++
        $operand = Read-DgRuleNotExpression -State $State
        $State.Depth--
        if ($operand.Kind -eq 'Comparison' -and $operand.Value.Kind -eq 'Null') {
            Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length `
                -Message '-not can''t be used with null; use -ne null or -eq null instead'
        }
        return [pscustomobject]@{
            PSTypeName = 'Dg.RuleNode'
            Kind       = 'Not'
            Operand    = $operand
            Position   = $token.Position
            Length     = $operand.Position + $operand.Length - $token.Position
        }
    }
    Read-DgRulePrimary -State $State
}
