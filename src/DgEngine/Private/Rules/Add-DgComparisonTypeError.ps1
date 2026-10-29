function Add-DgComparisonTypeError {
    <#
    .SYNOPSIS
        Checks that a comparison's operator and value fit the property type.
    .DESCRIPTION
        Text: every comparison operator except -le/-ge; values are text, numbers (compared as
        text) or null. Boolean: -eq/-ne with true, false (also quoted) or null. Date: -eq, -ne,
        -le, -ge with a date-time, system.now or null. -match/-notMatch need a valid .NET regex.
    .EXAMPLE
        Add-DgComparisonTypeError -Node $node -Type String -Label 'user.city' -Add $add
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'Boolean', 'Date')]
        [string] $Type,

        [Parameter(Mandatory)]
        [string] $Label,

        [Parameter(Mandatory)]
        [scriptblock] $Add
    )

    $operator = $Node.Operator
    $value = $Node.Value
    $operatorAt = { & $Add $Node.Property.Position ($value.Position - $Node.Property.Position) $args[0] }
    $values = if ($value.Kind -eq 'List') { $value.Items } else { @($value) }

    switch ($Type) {
        'String' {
            if ($operator -in @('le', 'ge')) {
                & $operatorAt "-$operator only works with dates; $Label is text"
                return
            }
            foreach ($v in $values) {
                if ($v.Kind -notin @('String', 'Number', 'Null')) {
                    & $Add $v.Position $v.Length "$Label is text; put the value in quotes"
                }
            }
            if ($operator -in @('match', 'notMatch') -and $value.Kind -eq 'String') {
                try {
                    [void][regex]::new($value.Value, 'IgnoreCase, CultureInvariant', [timespan]::FromMilliseconds(100))
                } catch {
                    $reason = $_.Exception.InnerException.Message
                    if (-not $reason) { $reason = $_.Exception.Message }
                    & $Add $value.Position $value.Length "invalid regular expression: $reason"
                }
            }
        }
        'Boolean' {
            if ($operator -notin @('eq', 'ne')) {
                & $operatorAt "$Label is true or false; use -eq or -ne"
                return
            }
            if (-not ($value.Kind -in @('Boolean', 'Null') -or ($value.Kind -eq 'String' -and $value.Value -in @('true', 'false')))) {
                & $Add $value.Position $value.Length "$Label is true or false; compare it with true or false"
            }
        }
        'Date' {
            if ($operator -notin @('eq', 'ne', 'le', 'ge')) {
                & $operatorAt "$Label is a date; use -eq, -ne, -le or -ge"
                return
            }
            $ok = $value.Kind -in @('Date', 'Now', 'Null')
            if (-not $ok -and $value.Kind -eq 'String') {
                $parsed = [DateTimeOffset]::MinValue
                $ok = [DateTimeOffset]::TryParse($value.Value, [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)
            }
            if (-not $ok) {
                & $Add $value.Position $value.Length "$Label is a date; use a date like 2026-01-31T00:00:00Z or system.now"
            }
        }
    }
}
