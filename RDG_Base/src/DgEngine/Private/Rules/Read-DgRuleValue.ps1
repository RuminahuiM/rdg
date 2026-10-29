function Read-DgRuleValue {
    <#
    .SYNOPSIS
        Reads the value after a comparison operator: a list for -in/-notIn, otherwise a scalar.
    .DESCRIPTION
        Also enforces the operator/value combinations that don't depend on the property type:
        null only with -eq/-ne, lists only with -in/-notIn and never empty.
    .EXAMPLE
        Read-DgRuleValue -State $state -Operator 'in'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [string] $Operator
    )

    $token = $State.Tokens[$State.Index]

    if ($Operator -in @('in', 'notIn')) {
        if ($token.Kind -ne 'LBracket') {
            Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length `
                -Message "-$Operator needs a list like [""a"",""b""]"
        }
        $State.Index++
        $items = [System.Collections.Generic.List[object]]::new()
        $next = $State.Tokens[$State.Index]
        if ($next.Kind -eq 'RBracket') {
            Invoke-DgRuleError -State $State -Position $token.Position -Length ($next.Position + 1 - $token.Position) -Message 'the list is empty'
        }
        while ($true) {
            $items.Add((Read-DgRuleScalar -State $State -Operator $Operator -InList))
            $separator = $State.Tokens[$State.Index]
            if ($separator.Kind -eq 'Comma') {
                $State.Index++
                continue
            }
            if ($separator.Kind -eq 'RBracket') {
                $State.Index++
                break
            }
            if ($separator.Kind -eq 'End') {
                Invoke-DgRuleError -State $State -Position $separator.Position -Length 0 `
                    -Message "missing ] to close the list at $(Get-DgRuleLocationText -State $State -Position $token.Position)"
            }
            Invoke-DgRuleError -State $State -Position $separator.Position -Length $separator.Length `
                -Message "expected , or ] in the list, found $($separator.Text)"
        }
        $close = $State.Tokens[$State.Index - 1]
        return [pscustomobject]@{
            PSTypeName = 'Dg.RuleValue'
            Kind       = 'List'
            Items      = $items.ToArray()
            Position   = $token.Position
            Length     = $close.Position + 1 - $token.Position
        }
    }

    if ($token.Kind -eq 'LBracket') {
        Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length `
            -Message 'a list is only allowed with -in and -notIn'
    }

    $value = Read-DgRuleScalar -State $State -Operator $Operator
    if ($value.Kind -eq 'Null' -and $Operator -notin @('eq', 'ne')) {
        Invoke-DgRuleError -State $State -Position $value.Position -Length $value.Length `
            -Message 'null can only be used with -eq or -ne'
    }
    $value
}
