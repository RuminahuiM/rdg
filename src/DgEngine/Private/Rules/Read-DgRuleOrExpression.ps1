function Read-DgRuleOrExpression {
    <#
    .SYNOPSIS
        orExpr = andExpr { "-or" andExpr }
    .EXAMPLE
        Read-DgRuleOrExpression -State $state
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $operands = [System.Collections.Generic.List[object]]::new()
    $operands.Add((Read-DgRuleAndExpression -State $State))
    while ($true) {
        $token = $State.Tokens[$State.Index]
        if ($token.Kind -eq 'Word' -and (Get-DgRuleOperatorName -Word $token.Value) -eq 'or') {
            $State.Index++
            $operands.Add((Read-DgRuleAndExpression -State $State))
        } else {
            break
        }
    }
    New-DgRuleLogicNode -Kind 'Or' -Operands $operands.ToArray()
}
