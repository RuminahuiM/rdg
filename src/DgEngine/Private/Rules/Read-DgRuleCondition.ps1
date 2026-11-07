function Read-DgRuleCondition {
    <#
    .SYNOPSIS
        comparison = property operator value; collectionTest = property (-any | -all) "(" orExpr ")"
    .EXAMPLE
        Read-DgRuleCondition -State $state
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $propertyToken = $State.Tokens[$State.Index]
    $property = ConvertTo-DgRuleProperty -State $State -Token $propertyToken
    $State.Index++

    $operatorToken = $State.Tokens[$State.Index]
    $propertyText = $propertyToken.Text
    if ($operatorToken.Kind -ne 'Word') {
        Invoke-DgRuleError -State $State -Position $operatorToken.Position -Length $operatorToken.Length `
            -Message "expected an operator such as -eq after $propertyText"
    }
    $operator = Get-DgRuleOperatorName -Word $operatorToken.Value
    if (-not $operator) {
        $suggestion = @{
            'equals' = 'eq'; '=' = 'eq'; '==' = 'eq'; '!=' = 'ne'; '<>' = 'ne'
            'notequals' = 'ne'; 'like' = 'match'; 'notlike' = 'notMatch'
            'gt' = 'ge'; 'lt' = 'le'; 'gte' = 'ge'; 'lte' = 'le'
        }[$operatorToken.Value.TrimStart('-').ToLowerInvariant()]
        $hint = if ($suggestion) { "; did you mean -${suggestion}?" } else { '' }
        Invoke-DgRuleError -State $State -Position $operatorToken.Position -Length $operatorToken.Length `
            -Message "unknown operator $($operatorToken.Text)$hint" -Suggestion $(if ($suggestion) { "-$suggestion" })
    }
    if ($operator -in @('and', 'or', 'not', 'plus', 'minus')) {
        Invoke-DgRuleError -State $State -Position $operatorToken.Position -Length $operatorToken.Length `
            -Message "expected an operator such as -eq after $propertyText, found -$operator"
    }
    $State.Index++

    if ($operator -in @('any', 'all')) {
        if ($State.InCollection) {
            Invoke-DgRuleError -State $State -Position $operatorToken.Position -Length $operatorToken.Length `
                -Message "-$operator can't be nested inside another -any or -all"
        }
        if ($property.Object -ne 'user') {
            Invoke-DgRuleError -State $State -Position $propertyToken.Position -Length $propertyToken.Length `
                -Message "-$operator needs a user property, e.g. user.proxyAddresses"
        }
        $open = $State.Tokens[$State.Index]
        if ($open.Kind -ne 'LParen') {
            Invoke-DgRuleError -State $State -Position $open.Position -Length $open.Length `
                -Message "expected ( after -$operator"
        }
        $State.Index++
        $State.InCollection = $true
        try {
            $condition = Read-DgRuleOrExpression -State $State
        } finally {
            $State.InCollection = $false
        }
        $close = $State.Tokens[$State.Index]
        if ($close.Kind -ne 'RParen') {
            Invoke-DgRuleError -State $State -Position $close.Position -Length $close.Length `
                -Message "missing ) to close the ( at $(Get-DgRuleLocationText -State $State -Position $open.Position)"
        }
        $State.Index++
        return [pscustomobject]@{
            PSTypeName = 'Dg.RuleNode'
            Kind       = 'Collection'
            Property   = $property
            Quantifier = $operator
            Condition  = $condition
            Position   = $propertyToken.Position
            Length     = $close.Position + 1 - $propertyToken.Position
        }
    }

    $value = Read-DgRuleValue -State $State -Operator $operator
    [pscustomobject]@{
        PSTypeName = 'Dg.RuleNode'
        Kind       = 'Comparison'
        Property   = $property
        Operator   = $operator
        Value      = $value
        Position   = $propertyToken.Position
        Length     = $value.Position + $value.Length - $propertyToken.Position
    }
}
