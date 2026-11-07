function Get-DgRuleSemanticError {
    <#
    .SYNOPSIS
        Checks a parsed rule against the property map and returns every problem found.
    .DESCRIPTION
        Unknown properties (with a "did you mean" suggestion), operators that don't fit the
        property type, values of the wrong type, invalid regular expressions, and the shapes
        -any/-all allow: _ for text collections, assignedPlan.<field> for assignedPlans, and for
        memberOf only -any (group.objectId -in [...]) with object IDs.
        Unlike the parser, this returns all errors, sorted by position.
    .EXAMPLE
        Get-DgRuleSemanticError -Rule $rule -Ast (ConvertTo-DgRuleAst -Rule $rule)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Rule',
        Justification = 'Used inside the $add script block to compute line and column.')]
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Rule,

        [Parameter(Mandatory)]
        [pscustomobject] $Ast
    )

    $errors = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([int] $Position, [int] $Length, [string] $Message, [string] $Suggestion)
        $errors.Add((New-DgRuleError -Rule $Rule -Position $Position -Length $Length -Message $Message -Suggestion $Suggestion))
    }
    $planFields = @('capabilityStatus', 'service', 'servicePlanId')

    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push(@{ Node = $Ast; Collection = $null })
    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $node = $item.Node
        $collection = $item.Collection
        switch ($node.Kind) {
            { $_ -in @('Or', 'And') } {
                foreach ($operand in $node.Operands) { $stack.Push(@{ Node = $operand; Collection = $collection }) }
            }
            'Not' {
                if ($collection -and $collection.Type -eq 'GroupCollection') {
                    & $add $node.Position $node.Length 'inside memberOf -any only group.objectId -in [...] is supported'
                } else {
                    $stack.Push(@{ Node = $node.Operand; Collection = $collection })
                }
            }
            'DirectReports' { }
            'Collection' {
                $entry = Resolve-DgRuleProperty -Name $node.Property.Name
                if (-not $entry) {
                    Add-DgUnknownPropertyError -Property $node.Property -Add $add
                    continue
                }
                if ($entry.Type -notin @('StringCollection', 'PlanCollection', 'GroupCollection')) {
                    & $add $node.Property.Position $node.Property.Length "-$($node.Quantifier) only works on properties with several values; user.$($entry.Name) has one"
                    continue
                }
                if ($entry.Type -eq 'GroupCollection') {
                    if ($node.Quantifier -ne 'any') {
                        & $add $node.Property.Position $node.Property.Length 'memberOf only supports -any, as in Entra'
                    }
                    if ($node.Condition.Kind -ne 'Comparison') {
                        & $add $node.Condition.Position $node.Condition.Length 'inside memberOf -any use a single condition: group.objectId -in [''<object ID>'']'
                        continue
                    }
                }
                $stack.Push(@{ Node = $node.Condition; Collection = $entry })
            }
            'Comparison' {
                $property = $node.Property
                $operator = $node.Operator
                $value = $node.Value

                if ($property.Object -eq 'user') {
                    $entry = Resolve-DgRuleProperty -Name $property.Name
                    if (-not $entry) {
                        Add-DgUnknownPropertyError -Property $property -Add $add
                        continue
                    }
                    if ($entry.Type -in @('StringCollection', 'PlanCollection', 'GroupCollection')) {
                        $example = switch ($entry.Type) {
                            'StringCollection' { "user.$($entry.Name) -any (_ -startsWith ""..."")" }
                            'PlanCollection' { 'user.assignedPlans -any (assignedPlan.service -eq "...")' }
                            'GroupCollection' { 'user.memberOf -any (group.objectId -in [''<object ID>''])' }
                        }
                        & $add $property.Position $property.Length "user.$($entry.Name) has several values; use -any or -all, e.g. $example"
                        continue
                    }
                    $type = $entry.Type
                    $label = "user.$($entry.Name)"
                } else {
                    # Item of a collection.
                    $expected = switch ($collection.Type) {
                        'StringCollection' { '_' }
                        'PlanCollection' { 'assignedPlan' }
                        'GroupCollection' { 'group' }
                    }
                    if ($property.Object -ne $expected) {
                        $hint = switch ($collection.Type) {
                            'StringCollection' { "refer to the items of user.$($collection.Name) as _" }
                            'PlanCollection' { "refer to the items of user.assignedPlans as assignedPlan.<field>" }
                            'GroupCollection' { 'inside memberOf -any use group.objectId' }
                        }
                        & $add $property.Position $property.Length $hint
                        continue
                    }
                    if ($collection.Type -eq 'PlanCollection' -and $property.Name -notin $planFields) {
                        & $add $property.Position $property.Length "assignedPlan has no field $($property.Name); use capabilityStatus, service or servicePlanId"
                        continue
                    }
                    if ($collection.Type -eq 'GroupCollection') {
                        if ($property.Name -ne 'objectId') {
                            & $add $property.Position $property.Length 'inside memberOf -any only group.objectId is supported'
                            continue
                        }
                        if ($operator -notin @('in', 'eq')) {
                            & $add $node.Position $node.Length 'inside memberOf -any use group.objectId -in [''<object ID>'']'
                            continue
                        }
                        $ids = if ($value.Kind -eq 'List') { $value.Items } else { @($value) }
                        foreach ($id in $ids) {
                            $parsed = [guid]::Empty
                            if ($id.Kind -ne 'String' -or -not [guid]::TryParse([string]$id.Value, [ref]$parsed)) {
                                & $add $id.Position $id.Length 'group IDs must be object IDs (GUIDs) in quotes'
                            }
                        }
                        continue
                    }
                    $type = 'String'
                    $label = if ($property.Object -eq '_') { 'the item' } else { "assignedPlan.$($property.Name)" }
                }

                Add-DgComparisonTypeError -Node $node -Type $type -Label $label -Add $add
            }
        }
    }

    $errors | Sort-Object -Property Position
}
