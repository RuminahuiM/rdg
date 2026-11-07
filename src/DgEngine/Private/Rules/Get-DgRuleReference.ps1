function Get-DgRuleReference {
    <#
    .SYNOPSIS
        Lists the user properties and group IDs a syntax tree refers to.
    .DESCRIPTION
        The snapshot loader reads only the referenced properties; the group resolver needs the
        referenced group IDs (memberOf). Property names are returned lower-case and unique.
    .EXAMPLE
        Get-DgRuleReference -Ast (ConvertTo-DgRuleAst -Rule 'user.city -eq "Bern"')
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Ast
    )

    $properties = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    $groupIds = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $usesManager = $false

    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push(@{ Node = $Ast; Collection = $null })
    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $node = $item.Node
        switch ($node.Kind) {
            { $_ -in @('Or', 'And') } {
                foreach ($operand in $node.Operands) { $stack.Push(@{ Node = $operand; Collection = $item.Collection }) }
            }
            'Not' {
                $stack.Push(@{ Node = $node.Operand; Collection = $item.Collection })
            }
            'Collection' {
                [void]$properties.Add($node.Property.Name.ToLowerInvariant())
                $stack.Push(@{ Node = $node.Condition; Collection = $node.Property.Name })
            }
            'Comparison' {
                if ($node.Property.Object -eq 'user') {
                    [void]$properties.Add($node.Property.Name.ToLowerInvariant())
                } elseif ($node.Property.Object -eq 'group' -and $item.Collection -eq 'memberOf') {
                    $values = if ($node.Value.Kind -eq 'List') { $node.Value.Items } else { @($node.Value) }
                    foreach ($value in $values) {
                        if ($value.Kind -eq 'String') { [void]$groupIds.Add($value.Value) }
                    }
                }
            }
            'DirectReports' {
                $usesManager = $true
            }
        }
    }

    [pscustomobject]@{
        PSTypeName  = 'Dg.RuleReference'
        Properties  = [string[]]@($properties)
        GroupIds    = [string[]]@($groupIds)
        UsesManager = $usesManager
    }
}
