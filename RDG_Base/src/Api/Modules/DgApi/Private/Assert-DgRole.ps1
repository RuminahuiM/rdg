function Assert-DgRole {
    <#
    .SYNOPSIS
        Ends the request with 403 unless the caller holds one of the allowed roles. Called once per
        endpoint with the roles from openapi.yaml (x-rdg-roles), in addition to the route rules.
    .EXAMPLE
        Assert-DgRole -Caller $caller -Allowed admin
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Caller,

        [Parameter(Mandatory)]
        [string[]] $Allowed
    )

    foreach ($role in $Caller.Roles) {
        if ($Allowed -contains $role) { return }
    }
    $needed = if ($Allowed -contains 'reader') { 'Reader or Admin' } else { 'Admin' }
    Stop-DgApi -Status 403 -Title 'Not allowed' -Detail "this needs the RDG role $needed"
}
