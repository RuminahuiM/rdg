function Invoke-DgRuleEvaluation {
    <#
    .SYNOPSIS
        Evaluates a compiled rule for every user and returns the ones that match.
    .EXAMPLE
        Invoke-DgRuleEvaluation -Compiled $compiled -Users $snapshot -Context $context
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Compiled,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Users,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $matched = [System.Collections.Generic.List[object]]::new()
    foreach ($user in $Users) {
        if (Test-DgRuleMatch -Node $Compiled -User $user -Context $Context) {
            $matched.Add($user)
        }
    }
    , $matched.ToArray()
}
