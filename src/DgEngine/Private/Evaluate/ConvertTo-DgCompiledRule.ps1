function ConvertTo-DgCompiledRule {
    <#
    .SYNOPSIS
        Prepares a validated syntax tree for evaluation: property entries resolved once, values
        converted once, regexes compiled once, lists turned into lookup sets.
    .DESCRIPTION
        Call only with a tree that passed Get-DgRuleSemanticError. The result is evaluated per
        user by Test-DgRuleMatch. Each definition is compiled once per run.
    .EXAMPLE
        $compiled = ConvertTo-DgCompiledRule -Ast (Test-DgRule -Rule $rule).Ast
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Node
    )

    switch ($Node.Kind) {
        { $_ -in @('Or', 'And') } {
            return [pscustomobject]@{
                Kind     = $Node.Kind
                Operands = [object[]]@($Node.Operands | ForEach-Object { ConvertTo-DgCompiledRule -Node $_ })
            }
        }
        'Not' {
            return [pscustomobject]@{ Kind = 'Not'; Operand = (ConvertTo-DgCompiledRule -Node $Node.Operand) }
        }
        'DirectReports' {
            return [pscustomobject]@{ Kind = 'DirectReports'; ManagerId = $Node.ManagerId }
        }
        'Collection' {
            $entry = Resolve-DgRuleProperty -Name $Node.Property.Name
            if ($entry.Type -eq 'GroupCollection') {
                $value = $Node.Condition.Value
                $ids = if ($value.Kind -eq 'List') { $value.Items } else { @($value) }
                return [pscustomobject]@{
                    Kind     = 'MemberOf'
                    GroupIds = [string[]]@($ids | ForEach-Object { ([guid]$_.Value).ToString() })
                }
            }
            return [pscustomobject]@{
                Kind       = 'Collection'
                Entry      = $entry
                Quantifier = $Node.Quantifier
                Condition  = (ConvertTo-DgCompiledRule -Node $Node.Condition)
            }
        }
        'Comparison' {
            $property = $Node.Property
            $entry = $null
            $type = 'String'
            if ($property.Object -eq 'user') {
                $entry = Resolve-DgRuleProperty -Name $property.Name
                $type = $entry.Type
            }
            $operator = $Node.Operator
            $value = $Node.Value
            $compiled = [ordered]@{
                Kind     = 'Comparison'
                Entry    = $entry
                Item     = if ($property.Object -eq 'user') {
                    $null
                } elseif ($property.Object -eq '_') {
                    '_'
                } else {
                    # Graph field names are case-sensitive; use Graph's spelling whatever the rule says.
                    @('capabilityStatus', 'service', 'servicePlanId') | Where-Object { $_ -eq $property.Name } | Select-Object -First 1
                }
                Type     = $type
                Operator = $operator
                Expected = $null
                IsNull   = $value.Kind -eq 'Null'
                Set      = $null
                Regex    = $null
                Offset   = $null
            }
            $invariant = [System.Globalization.CultureInfo]::InvariantCulture
            switch ($type) {
                'String' {
                    if ($value.Kind -eq 'List') {
                        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($v in $value.Items) { [void]$set.Add([string]::Format($invariant, '{0}', $v.Value)) }
                        $compiled.Set = $set
                    } elseif ($value.Kind -ne 'Null') {
                        $compiled.Expected = [string]::Format($invariant, '{0}', $value.Value)
                        if ($operator -in @('match', 'notMatch')) {
                            $compiled.Regex = [regex]::new($compiled.Expected, 'IgnoreCase, CultureInvariant', [timespan]::FromMilliseconds(100))
                        }
                    }
                }
                'Boolean' {
                    if ($value.Kind -eq 'Boolean') { $compiled.Expected = [bool]$value.Value }
                    elseif ($value.Kind -eq 'String') { $compiled.Expected = $value.Value -eq 'true' }
                }
                'Date' {
                    if ($value.Kind -eq 'Date') { $compiled.Expected = [DateTimeOffset]$value.Value }
                    elseif ($value.Kind -eq 'Now') { $compiled.Offset = [timespan]$value.Value }
                    elseif ($value.Kind -eq 'String') {
                        $compiled.Expected = [DateTimeOffset]::Parse($value.Value, $invariant, [System.Globalization.DateTimeStyles]::AssumeUniversal)
                    }
                }
            }
            return [pscustomobject]$compiled
        }
    }
}
