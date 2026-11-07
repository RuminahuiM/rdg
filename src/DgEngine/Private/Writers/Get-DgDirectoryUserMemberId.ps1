function Get-DgDirectoryUserMemberId {
    <#
    .SYNOPSIS
        The memberOf provider: the user IDs in a group, nested or direct.
    .DESCRIPTION
        Returns Found = $false when the group doesn't exist. Always Graph (any group type).
    .EXAMPLE
        Get-DgDirectoryUserMemberId -Directory $graph -GroupId $id -Transitive $true
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [bool] $Transitive
    )

    if ($Directory.Kind -eq 'Custom') {
        return & $Directory.GetUserMemberIds -GroupId $GroupId -Transitive $Transitive
    }
    $relation = if ($Transitive) { 'transitiveMembers' } else { 'members' }
    try {
        $items = Get-DgGraphCollection -Directory $Directory -Uri "/groups/$GroupId/$relation/microsoft.graph.user?`$select=id&`$top=999"
    } catch {
        if ((Get-DgTransientError -ErrorRecord $_).StatusCode -eq 404) {
            return [pscustomobject]@{ Found = $false; UserIds = @() }
        }
        throw
    }
    [pscustomobject]@{
        Found   = $true
        UserIds = [string[]]@($items | ForEach-Object { [string](Get-DgFieldValue -Object $_ -Name 'id') })
    }
}
