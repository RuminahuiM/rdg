function New-DgRuleError {
    <#
    .SYNOPSIS
        Creates a rule error with position, line and column.
    .DESCRIPTION
        Position is the 0-based character offset in the rule text; Line and Column are 1-based for
        display. Length is the number of characters the editor underlines.
    .EXAMPLE
        New-DgRuleError -Rule $rule -Position 21 -Message 'expected a value after -eq'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Rule,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Position,

        [ValidateRange(0, [int]::MaxValue)]
        [int] $Length = 1,

        [Parameter(Mandatory)]
        [string] $Message,

        [string] $Suggestion
    )

    $offset = [Math]::Min($Position, $Rule.Length)
    $before = $Rule.Substring(0, $offset)
    $line = [regex]::Matches($before, "`n").Count + 1
    $column = $offset - $before.LastIndexOf("`n")

    [pscustomobject]@{
        PSTypeName = 'Dg.RuleError'
        Position   = $offset
        Line       = $line
        Column     = $column
        Length     = $Length
        Message    = $Message
        Suggestion = if ($Suggestion) { $Suggestion } else { $null }
    }
}
