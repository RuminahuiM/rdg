function Write-DgHeartbeat {
    <#
    .SYNOPSIS
        Overwrites the runbook's heartbeat document (written every tick, also when paused).
    .DESCRIPTION
        userCount is the size of the last healthy user snapshot; the next run compares against
        it (snapshot health). Pass the previous count when this run didn't read a healthy one.
    .EXAMPLE
        Write-DgHeartbeat -Store $store -Provider Entra -JobId $jobId -Now $now -Paused $false -AccessMode read-write -UserCount 2000
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Store,

        [Parameter(Mandatory)]
        [ValidateSet('Entra', 'Exchange')]
        [string] $Provider,

        [Parameter(Mandatory)]
        [string] $JobId,

        [Parameter(Mandatory)]
        [DateTimeOffset] $Now,

        [Parameter(Mandatory)]
        [bool] $Paused,

        [Parameter(Mandatory)]
        [ValidateSet('read-only', 'read-write')]
        [string] $AccessMode,

        [Nullable[int]] $UserCount
    )

    $document = [ordered]@{
        id            = "heartbeat-$Provider"
        pk            = 'system'
        type          = 'heartbeat'
        schemaVersion = 1
        runbook       = $Provider
        at            = ConvertTo-DgTimestamp -Value $Now
        jobId         = $JobId
        engineVersion = Get-DgEngineVersion
        paused        = $Paused
        accessMode    = $AccessMode
    }
    if ($null -ne $UserCount) { $document.userCount = [int]$UserCount }
    if (-not $PSCmdlet.ShouldProcess($document.id, 'Write heartbeat')) { return $false }
    Set-DgStoreItem -Store $Store -Container state -Document $document
}
