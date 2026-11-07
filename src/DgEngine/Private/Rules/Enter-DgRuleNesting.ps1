function Enter-DgRuleNesting {
    <#
    .SYNOPSIS
        Counts one more nesting level (parenthesis or -not) and stops beyond the limit.
    .DESCRIPTION
        The caller decrements $State.Depth when the nested part is done.
    .EXAMPLE
        Enter-DgRuleNesting -State $state -Token $token
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [pscustomobject] $Token,

        [int] $MaxDepth = 100
    )

    $State.Depth++
    if ($State.Depth -gt $MaxDepth) {
        Invoke-DgRuleError -State $State -Position $Token.Position -Length $Token.Length `
            -Message "the rule is nested more than $MaxDepth levels deep"
    }
}
