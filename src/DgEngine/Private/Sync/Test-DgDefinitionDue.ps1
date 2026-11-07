function Test-DgDefinitionDue {
    <#
    .SYNOPSIS
        Decides whether a definition runs in this tick. Returns the reason (Requested, NeverRun,
        Schedule, Named) or $null.
    .DESCRIPTION
        Disabled definitions never run. A sync-now request newer than the last handled one is
        always due. A SyncNow run handles only requests (or the one named definition). A
        scheduled run also takes definitions whose interval is over, with one minute of
        tolerance; intervals shorter than the tick count as one tick.
    .EXAMPLE
        Test-DgDefinitionDue -Item $item -Now $now -TickMinutes 3 -Mode Scheduled
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Item,

        [Parameter(Mandatory)]
        [DateTimeOffset] $Now,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1440)]
        [int] $TickMinutes,

        [Parameter(Mandatory)]
        [ValidateSet('Scheduled', 'SyncNow')]
        [string] $Mode,

        [string] $DefinitionId
    )

    if (-not $Item.Enabled) { return $null }
    if ($DefinitionId) {
        if ($Item.Id -eq $DefinitionId) { return 'Named' }
        return $null
    }
    $handled = $Item.Status.HandledSyncRequestAt
    if ($Item.SyncRequestAt -and (-not $handled -or $Item.SyncRequestAt -gt $handled)) { return 'Requested' }
    if ($Mode -eq 'SyncNow') { return $null }
    if (-not $Item.LastSyncUtc) { return 'NeverRun' }
    $interval = [Math]::Max($Item.FrequencyMinutes, $TickMinutes)
    if ($Now -ge $Item.LastSyncUtc.AddMinutes($interval - 1)) { return 'Schedule' }
    $null
}
