function Get-DgGraphCollection {
    <#
    .SYNOPSIS
        Reads a Graph collection completely, following @odata.nextLink.
    .DESCRIPTION
        A failing page fails the whole read: a partial user or member list must never be used.
    .EXAMPLE
        Get-DgGraphCollection -Directory $graph -Uri '/users?$select=id&$top=999'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [string] $Uri
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $page = Invoke-DgGraphRequest -Directory $Directory -Method GET -Uri $next
        foreach ($item in @(Get-DgFieldValue -Object $page -Name 'value')) {
            foreach ($entry in @($item)) { if ($null -ne $entry) { $items.Add($entry) } }
        }
        $next = [string](Get-DgFieldValue -Object $page -Name '@odata.nextLink')
    }
    , $items.ToArray()
}
