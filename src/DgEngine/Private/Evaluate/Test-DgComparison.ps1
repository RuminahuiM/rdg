function Test-DgComparison {
    <#
    .SYNOPSIS
        Compares one actual value with a compiled comparison. See Test-DgRuleMatch for the rules.
    .EXAMPLE
        Test-DgComparison -Node $comparison -Actual 'Sales' -Context $context
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [AllowNull()]
        [object] $Actual,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $operator = $Node.Operator
    $negated = $operator -in @('ne', 'notStartsWith', 'notEndsWith', 'notContains', 'notMatch', 'notIn')
    $positive = switch ($operator) {
        'ne' { 'eq' } 'notStartsWith' { 'startsWith' } 'notEndsWith' { 'endsWith' }
        'notContains' { 'contains' } 'notMatch' { 'match' } 'notIn' { 'in' }
        default { $operator }
    }

    if ($Node.IsNull) {
        return (($null -eq $Actual) -xor $negated)
    }
    if ($null -eq $Actual) {
        return $negated
    }

    $result = $false
    switch ($Node.Type) {
        'Boolean' {
            $actualBool = $false
            if ($Actual -is [bool]) {
                $actualBool = $Actual
            } elseif (-not [bool]::TryParse([string]$Actual, [ref]$actualBool)) {
                return $negated
            }
            $result = $actualBool -eq $Node.Expected
        }
        'Date' {
            $actualDate = [DateTimeOffset]::MinValue
            $parsed = if ($Actual -is [DateTimeOffset]) {
                $actualDate = $Actual; $true
            } elseif ($Actual -is [datetime]) {
                # Graph times are UTC; only an unspecified kind is taken as UTC, Local and Utc keep their meaning.
                $actualDate = if ($Actual.Kind -eq [DateTimeKind]::Unspecified) {
                    [DateTimeOffset]::new([datetime]::SpecifyKind($Actual, [DateTimeKind]::Utc))
                } else {
                    [DateTimeOffset]::new($Actual)
                }
                $true
            } else {
                [DateTimeOffset]::TryParse([string]$Actual, [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$actualDate)
            }
            if (-not $parsed) { return $negated }
            $expected = if ($null -ne $Node.Offset) { ([DateTimeOffset]$Context.Now).Add($Node.Offset) } else { $Node.Expected }
            $result = switch ($positive) {
                'eq' { $actualDate -eq $expected }
                'le' { $actualDate -le $expected }
                'ge' { $actualDate -ge $expected }
            }
        }
        default {
            $text = if ($Actual -is [bool]) {
                if ($Actual) { 'true' } else { 'false' }
            } else {
                [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Actual)
            }
            $ignoreCase = [System.StringComparison]::OrdinalIgnoreCase
            $result = switch ($positive) {
                'eq' { [string]::Equals($text, $Node.Expected, $ignoreCase) }
                'startsWith' { $text.StartsWith($Node.Expected, $ignoreCase) }
                'endsWith' { $text.EndsWith($Node.Expected, $ignoreCase) }
                'contains' { $text.IndexOf($Node.Expected, $ignoreCase) -ge 0 }
                'in' { $Node.Set.Contains($text) }
                'match' {
                    try {
                        $Node.Regex.IsMatch($text)
                    } catch {
                        # .NET exceptions arrive wrapped in a MethodInvocationException.
                        $inner = $_.Exception
                        while ($inner -and $inner -isnot [System.Text.RegularExpressions.RegexMatchTimeoutException]) { $inner = $inner.InnerException }
                        if ($inner) {
                            throw [System.InvalidOperationException]::new("the regular expression ""$($Node.Expected)"" took longer than 100 ms")
                        }
                        throw
                    }
                }
            }
        }
    }
    [bool]$result -xor $negated
}
