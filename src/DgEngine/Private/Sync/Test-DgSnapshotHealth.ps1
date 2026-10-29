function Test-DgSnapshotHealth {
    <#
    .SYNOPSIS
        Refuses a user snapshot that looks incomplete, which would otherwise remove members everywhere.
    .DESCRIPTION
        Returns $null when the snapshot is fine, or a message when the whole run must stop: no
        users at all, or fewer than 80 % of the users the previous run saw (only once the
        previous run saw at least 20). There is no override; a genuine drop of more than 20 % of
        all users in one tick is rare enough to need a person to look at it.
    .EXAMPLE
        Test-DgSnapshotHealth -UserCount $users.Count -PreviousUserCount $heartbeat.userCount
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $UserCount,

        [AllowNull()]
        [Nullable[int]] $PreviousUserCount
    )

    if ($UserCount -eq 0) {
        return 'the user list is empty; the run stopped so that no group is emptied'
    }
    if ($null -ne $PreviousUserCount -and $PreviousUserCount -ge 20 -and $UserCount -lt 0.8 * $PreviousUserCount) {
        return "the user list has $UserCount users, fewer than 80 % of the $PreviousUserCount the previous run saw; the run stopped so that no group loses members by mistake"
    }
    $null
}
