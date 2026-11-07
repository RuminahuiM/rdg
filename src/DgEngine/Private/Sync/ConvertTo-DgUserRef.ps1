function ConvertTo-DgUserRef {
    <#
    .SYNOPSIS
        Turns user IDs into the {id, upn, displayName} entries of run records, at most 500.
    .EXAMPLE
        ConvertTo-DgUserRef -Ids $plan.Adds -UsersById $usersById
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Ids,

        [Parameter(Mandatory)]
        [hashtable] $UsersById,

        [int] $Limit = 500
    )

    $refs = [System.Collections.Generic.List[object]]::new()
    foreach ($id in ($Ids | Select-Object -First $Limit)) {
        $user = $UsersById[$id]
        $ref = [ordered]@{
            id  = $id.ToLowerInvariant()
            upn = if ($user) { [string](Get-DgFieldValue -Object $user -Name 'userPrincipalName') } else { '' }
        }
        $name = if ($user) { [string](Get-DgFieldValue -Object $user -Name 'displayName') } else { '' }
        if ($name) { $ref.displayName = $name }
        $refs.Add($ref)
    }
    , $refs.ToArray()
}
