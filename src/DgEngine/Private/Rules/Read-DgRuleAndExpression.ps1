function Read-DgRuleAndExpression {
    <#
    .SYNOPSIS
        andExpr = notExpr { "-and" notExpr }
    .EXAMPLE
        Read-DgRuleAndExpression -State $state
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $operands = [System.Collections.Generic.List[object]]::new()
    $operands.Add((Read-DgRuleNotExpression -State $State))
    while ($true) {
        $token = $State.Tokens[$State.Index]
        if ($token.Kind -eq 'Word' -and (Get-DgRuleOperatorName -Word $token.Value) -eq 'and') {
            $State.Index++
            $operands.Add((Read-DgRuleNotExpression -State $State))
        } else {
            break
        }
    }
    New-DgRuleLogicNode -Kind 'And' -Operands $operands.ToArray()
}
