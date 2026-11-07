function Get-DgRuleLocationText {
    <#
    .SYNOPSIS
        Describes a position for error messages: "column 5" on a one-line rule, "line 2, column 5" otherwise.
    .EXAMPLE
        "missing ) to close the ( at $(Get-DgRuleLocationText -State $state -Position 4)"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [int] $Position
    )

    $location = New-DgRuleError -Rule $State.Rule -Position $Position -Message 'location'
    if ($State.Rule.Contains("`n")) {
        return "line $($location.Line), column $($location.Column)"
    }
    "column $($location.Column)"
}
