function Get-DgCompareResult {
    <#
    .SYNOPSIS
        Compares RDG's result with a compare group: who is only in RDG, who only in the group.
    .DESCRIPTION
        Users is the snapshot, used to show UPNs. Lists are capped at 500 entries like run
        records; the counts are always complete.
    .EXAMPLE
        Get-DgCompareResult -GroupId $compareId -DesiredIds $desired.MemberIds -CompareIds $groupIds -Users $users
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $DesiredIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $CompareIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Users
    )

    $compare = [System.Collections.Generic.HashSet[string]]::new([string[]]@($CompareIds), [System.StringComparer]::OrdinalIgnoreCase)
    $byId = @{}
    foreach ($user in $Users) { $byId[[string](Get-DgFieldValue -Object $user -Name 'id')] = $user }
    $toRef = {
        param($id)
        $user = $byId[$id]
        $upn = if ($user) { [string](Get-DgFieldValue -Object $user -Name 'userPrincipalName') } else { '' }
        [pscustomobject]@{ id = $id.ToLowerInvariant(); upn = $upn }
    }
    $onlyInRdg = @($DesiredIds | Where-Object { -not $compare.Contains($_) } | Sort-Object)
    $onlyInCompare = @($compare | Where-Object { -not $DesiredIds.Contains($_) } | Sort-Object)

    [pscustomobject]@{
        groupId            = $GroupId.ToLowerInvariant()
        onlyInRdgCount     = $onlyInRdg.Count
        onlyInCompareCount = $onlyInCompare.Count
        onlyInRdg          = [object[]]@($onlyInRdg | Select-Object -First 500 | ForEach-Object { & $toRef $_ })
        onlyInCompare      = [object[]]@($onlyInCompare | Select-Object -First 500 | ForEach-Object { & $toRef $_ })
    }
}
