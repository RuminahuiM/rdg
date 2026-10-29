function Get-DgMemberDiff {
    <#
    .SYNOPSIS
        Compares the desired users with a group's current members.
    .DESCRIPTION
        CurrentMembers are objects with Id and IsUser (from the directory adapter). Only users
        are added or removed: nested groups, contacts, devices and other non-user members are
        left alone. Adds and Removes are sorted, lower-case user IDs.
    .EXAMPLE
        Get-DgMemberDiff -DesiredIds $desired.MemberIds -CurrentMembers $current
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $DesiredIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $CurrentMembers
    )

    $currentUsers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $nonUsers = 0
    foreach ($member in $CurrentMembers) {
        if (Get-DgFieldValue -Object $member -Name 'IsUser') {
            [void]$currentUsers.Add([string](Get-DgFieldValue -Object $member -Name 'Id'))
        } else {
            $nonUsers++
        }
    }

    $adds = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $DesiredIds) {
        if (-not $currentUsers.Contains($id)) { $adds.Add($id.ToLowerInvariant()) }
    }
    $removes = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $currentUsers) {
        if (-not $DesiredIds.Contains($id)) { $removes.Add($id.ToLowerInvariant()) }
    }
    $adds.Sort([System.StringComparer]::Ordinal)
    $removes.Sort([System.StringComparer]::Ordinal)

    [pscustomobject]@{
        PSTypeName       = 'Dg.MemberDiff'
        Adds             = $adds.ToArray()
        Removes          = $removes.ToArray()
        CurrentUserCount = $currentUsers.Count
        NonUserMembers   = $nonUsers
        CurrentUserIds   = $currentUsers
    }
}
