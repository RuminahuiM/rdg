function New-DgSystemRunDocument {
    <#
    .SYNOPSIS
        The run record for a tick that did no work: SkippedTick (another job holds the lock) or Paused.
    .EXAMPLE
        New-DgSystemRunDocument -JobId $jobId -Provider Entra -Mode Scheduled -StartedAt $now -DurationMs 40 -Result Paused -Reason 'paused by admin@contoso.org'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $JobId,

        [Parameter(Mandatory)]
        [ValidateSet('Entra', 'Exchange')]
        [string] $Provider,

        [Parameter(Mandatory)]
        [ValidateSet('Scheduled', 'SyncNow')]
        [string] $Mode,

        [Parameter(Mandatory)]
        [DateTimeOffset] $StartedAt,

        [Parameter(Mandatory)]
        [long] $DurationMs,

        [Parameter(Mandatory)]
        [ValidateSet('SkippedTick', 'Paused')]
        [string] $Result,

        [string] $Reason
    )

    $document = [ordered]@{
        id            = "run-$($JobId.ToLowerInvariant())-system"
        pk            = 'system'
        type          = 'run'
        schemaVersion = 1
        jobId         = $JobId.ToLowerInvariant()
        runbook       = $Provider
        mode          = $Mode
        startedAt     = ConvertTo-DgTimestamp -Value $StartedAt
        durationMs    = [Math]::Max([long]0, $DurationMs)
        result        = $Result
        engineVersion = Get-DgEngineVersion
    }
    if ($Reason) { $document.reason = if ($Reason.Length -gt 1000) { $Reason.Substring(0, 1000) } else { $Reason } }
    $document
}
