function New-DgRuleLogicNode {
    <#
    .SYNOPSIS
        Builds an Or/And node, or returns the single operand unchanged.
    .EXAMPLE
        New-DgRuleLogicNode -Kind And -Operands @($left, $right)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Or', 'And')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [object[]] $Operands
    )

    if ($Operands.Count -eq 1) {
        return $Operands[0]
    }
    $first = $Operands[0]
    $last = $Operands[$Operands.Count - 1]
    [pscustomobject]@{
        PSTypeName = 'Dg.RuleNode'
        Kind       = $Kind
        Operands   = $Operands
        Position   = $first.Position
        Length     = $last.Position + $last.Length - $first.Position
    }
}
