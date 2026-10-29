function Read-DgRulePrimary {
    <#
    .SYNOPSIS
        primary = "(" orExpr ")" | collectionTest | comparison
    .EXAMPLE
        Read-DgRulePrimary -State $state
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $token = $State.Tokens[$State.Index]
    switch ($token.Kind) {
        'LParen' {
            Enter-DgRuleNesting -State $State -Token $token
            $State.Index++
            $inner = Read-DgRuleOrExpression -State $State
            $State.Depth--
            $closing = $State.Tokens[$State.Index]
            if ($closing.Kind -ne 'RParen') {
                Invoke-DgRuleError -State $State -Position $closing.Position -Length $closing.Length `
                    -Message "missing ) to close the ( at $(Get-DgRuleLocationText -State $State -Position $token.Position)"
            }
            $State.Index++
            return $inner
        }
        'Word' {
            return Read-DgRuleCondition -State $State
        }
        'String' {
            Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length `
                -Message "expected a property like user.department before $($token.Text)"
        }
        default {
            Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length `
                -Message "expected a condition$(Get-DgRuleContext -State $State)"
        }
    }
}
