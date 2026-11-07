function Read-DgRuleScalar {
    <#
    .SYNOPSIS
        Reads one value: a quoted string, a number, true, false, null, an ISO 8601 date-time or
        system.now with an optional -plus/-minus ISO 8601 duration.
    .DESCRIPTION
        Unquoted text is refused with a hint to add quotes, as Entra requires quotes for strings.
        In a list only strings, numbers and booleans are allowed.
    .EXAMPLE
        Read-DgRuleScalar -State $state -Operator 'eq'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [string] $Operator,

        [switch] $InList
    )

    $token = $State.Tokens[$State.Index]
    $new = {
        param([string] $Kind, [object] $Value, [int] $Length = $token.Length)
        [pscustomobject]@{
            PSTypeName = 'Dg.RuleValue'
            Kind       = $Kind
            Value      = $Value
            Position   = $token.Position
            Length     = $Length
        }
    }
    $where = if ($InList) { 'in the list' } else { "after -$Operator" }

    if ($token.Kind -eq 'String') {
        $State.Index++
        return & $new 'String' $token.Value
    }
    if ($token.Kind -ne 'Word' -or (Get-DgRuleOperatorName -Word $token.Value)) {
        $found = if ($token.Kind -eq 'End') { '' } else { ", found $($token.Text)" }
        Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length `
            -Message "expected a value $where$found"
    }

    $text = $token.Value
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    if ($text -eq 'null') {
        if ($InList) {
            Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length -Message 'null is not allowed in a list'
        }
        $State.Index++
        return & $new 'Null' $null
    }
    if ($text -eq 'true' -or $text -eq 'false') {
        $State.Index++
        return & $new 'Boolean' ($text -eq 'true')
    }
    if ($text -match '^-?\d+(\.\d+)?$') {
        $State.Index++
        return & $new 'Number' ([decimal]::Parse($text, $invariant))
    }
    if ($text -match '^\d{4}-\d{2}-\d{2}([Tt ][0-9:.]+([Zz]|[+-]\d{2}:\d{2})?)?$') {
        if ($InList) {
            Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length -Message 'dates are not allowed in a list'
        }
        $parsed = [DateTimeOffset]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal
        if (-not [DateTimeOffset]::TryParse($text, $invariant, $styles, [ref]$parsed)) {
            Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length -Message "$text is not a valid date"
        }
        $State.Index++
        return & $new 'Date' $parsed.ToUniversalTime()
    }
    if ($text -eq 'system.now') {
        if ($InList) {
            Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length -Message 'system.now is not allowed in a list'
        }
        $State.Index++
        $offset = [timespan]::Zero
        $length = $token.Length
        $signToken = $State.Tokens[$State.Index]
        $sign = if ($signToken.Kind -eq 'Word') { Get-DgRuleOperatorName -Word $signToken.Value } else { $null }
        if ($sign -in @('plus', 'minus')) {
            $State.Index++
            $durationToken = $State.Tokens[$State.Index]
            if ($durationToken.Kind -ne 'Word') {
                Invoke-DgRuleError -State $State -Position $durationToken.Position -Length $durationToken.Length `
                    -Message "expected a duration like P1D after -$sign"
            }
            try {
                $offset = [System.Xml.XmlConvert]::ToTimeSpan($durationToken.Value.ToUpperInvariant())
            } catch {
                # .NET exceptions arrive wrapped (MethodInvocationException); any failure means a bad duration.
                Invoke-DgRuleError -State $State -Position $durationToken.Position -Length $durationToken.Length `
                    -Message "$($durationToken.Text) is not an ISO 8601 duration; use e.g. P1D, P2W or PT12H"
            }
            if ($sign -eq 'minus') {
                $offset = $offset.Negate()
            }
            $State.Index++
            $length = $durationToken.Position + $durationToken.Length - $token.Position
        }
        return & $new 'Now' $offset $length
    }

    Invoke-DgRuleError -State $State -Position $token.Position -Length $token.Length `
        -Message "text values need quotes: ""$text""" -Suggestion """$text"""
}
