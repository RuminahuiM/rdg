function Get-DgDirectoryObjectById {
    <#
    .SYNOPSIS
        Reads users and groups by ID, for showing names in the web app. IDs that no longer exist
        are left out.
    .DESCRIPTION
        One Graph JSON $batch per 20 IDs: GET /users/{id} for user IDs and GET /groups/{id} for
        group IDs, so User.Read.All and GroupMember.Read.All are enough. (directoryObjects/getByIds
        would need Directory.Read.All, which RDG does not grant.) Returned objects carry id,
        displayName and, for users, userPrincipalName. A failed batch entry other than 404 throws.
    .EXAMPLE
        Get-DgDirectoryObjectById -Directory $graph -UserIds @($userId) -GroupIds @($groupId)
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [AllowEmptyCollection()]
        [string[]] $UserIds = @(),

        [AllowEmptyCollection()]
        [string[]] $GroupIds = @()
    )

    $unique = { param([string[]] $Ids) [string[]]@($Ids | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique) }
    # Wrapped again: a scriptblock returning one ID would otherwise unroll to a string.
    $users = [string[]]@(& $unique $UserIds)
    $groups = [string[]]@(& $unique $GroupIds)
    if ($users.Count + $groups.Count -eq 0) {
        return , [object[]]@()
    }
    if ($Directory.Kind -eq 'Custom') {
        return , [object[]]@(& $Directory.GetObjectsById -Ids ([string[]]@($users + $groups)))
    }

    $urls = [string[]]@(
        foreach ($id in $users) { "/users/$id`?`$select=id,displayName,userPrincipalName" }
        foreach ($id in $groups) { "/groups/$id`?`$select=id,displayName" }
    )
    $found = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $urls.Count; $i += 20) {
        $chunk = [string[]]@($urls[$i..([Math]::Min($i + 19, $urls.Count - 1))])
        $requests = for ($k = 0; $k -lt $chunk.Count; $k++) { @{ id = [string]$k; method = 'GET'; url = $chunk[$k] } }
        $response = Invoke-DgGraphRequest -Directory $Directory -Method POST -Uri '/$batch' -Body @{ requests = @($requests) }
        foreach ($entry in @(Get-DgFieldValue -Object $response -Name 'responses')) {
            foreach ($item in @($entry)) {
                $status = [int](Get-DgFieldValue -Object $item -Name 'status')
                if ($status -eq 200) {
                    $found.Add((Get-DgFieldValue -Object $item -Name 'body'))
                } elseif ($status -ne 404) {
                    throw "Graph batch request $($chunk[[int](Get-DgFieldValue -Object $item -Name 'id')]) failed with status $status"
                }
            }
        }
    }
    , [object[]]$found.ToArray()
}
