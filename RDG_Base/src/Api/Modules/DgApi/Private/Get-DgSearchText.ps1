function Get-DgSearchText {
    <#
    .SYNOPSIS
        Reads the picker's search text: 2 to 100 characters, otherwise 400.
    .EXAMPLE
        $search = Get-DgSearchText -Request $Request
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Request
    )

    $search = ([string](Get-DgRequestValue -Request $Request -Part Query -Name search)).Trim()
    if ($search.Length -lt 2 -or $search.Length -gt 100) {
        Stop-DgApi -Status 400 -Title 'search needs 2 to 100 characters' -Type 'validation' -Extra @{ errors = @([ordered]@{ field = 'search'; message = 'use 2 to 100 characters' }) }
    }
    $search
}
