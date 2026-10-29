function Format-DgRuleAst {
    <#
    .SYNOPSIS
        Renders a syntax tree as a compact, canonical text, e.g. (or (eq user.city "Bern") (not ...)).
    .DESCRIPTION
        Used by the conformance suite to state the expected tree in data files, and in logs.
        Operators are lower-case canonical names; property names keep the case they were written in.
    .EXAMPLE
        Format-DgRuleAst -Node (ConvertTo-DgRuleAst -Rule 'user.city -eq "Bern"')   # (eq user.city "Bern")
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Node
    )

    $formatValue = {
        param($Value)
        switch ($Value.Kind) {
            'String' { '"' + $Value.Value.Replace('\', '\\').Replace('"', '\"') + '"' }
            'Number' { $Value.Value.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            'Boolean' { if ($Value.Value) { 'true' } else { 'false' } }
            'Null' { 'null' }
            'Date' { '@' + $Value.Value.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture) }
            'Now' {
                if ($Value.Value -eq [timespan]::Zero) { 'now' }
                elseif ($Value.Value -lt [timespan]::Zero) { 'now-' + [System.Xml.XmlConvert]::ToString($Value.Value.Negate()) }
                else { 'now+' + [System.Xml.XmlConvert]::ToString($Value.Value) }
            }
            'List' { '[' + (($Value.Items | ForEach-Object { & $formatValue $_ }) -join ' ') + ']' }
        }
    }
    $formatProperty = {
        param($Property)
        if ($Property.Object -eq '_') { '_' } else { "$($Property.Object).$($Property.Name)" }
    }

    switch ($Node.Kind) {
        'Or' { '(or ' + (($Node.Operands | ForEach-Object { Format-DgRuleAst -Node $_ }) -join ' ') + ')' }
        'And' { '(and ' + (($Node.Operands | ForEach-Object { Format-DgRuleAst -Node $_ }) -join ' ') + ')' }
        'Not' { '(not ' + (Format-DgRuleAst -Node $Node.Operand) + ')' }
        'Comparison' { "($($Node.Operator) $(& $formatProperty $Node.Property) $(& $formatValue $Node.Value))" }
        'Collection' { "($($Node.Quantifier) $(& $formatProperty $Node.Property) $(Format-DgRuleAst -Node $Node.Condition))" }
        'DirectReports' { "(directReports $($Node.ManagerId))" }
        default { throw "unknown node kind $($Node.Kind)" }
    }
}
