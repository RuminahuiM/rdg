function Get-DgRuleContext {
    <#
    .SYNOPSIS
        Returns " after <previous token>" for error messages, or an empty string at the start.
    .EXAMPLE
        "expected a condition$(Get-DgRuleContext -State $state)"   # expected a condition after -and
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    if ($State.Index -le 0) {
        return ''
    }
    $previous = $State.Tokens[$State.Index - 1]
    $text = $previous.Value
    if ($previous.Kind -eq 'Word') {
        $operator = Get-DgRuleOperatorName -Word $text
        if ($operator) {
            $text = "-$operator"
        }
    }
    " after $text"
}
