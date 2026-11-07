function ConvertTo-DgApiStatus {
    <#
    .SYNOPSIS
        Maps the engine's status document to the API's Status object (read-only fields only;
        internal hashes stay inside).
    .EXAMPLE
        ConvertTo-DgApiStatus -Document $status
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowNull()]
        [System.Collections.IDictionary] $Document
    )

    if (-not $Document) { return $null }
    $excluded = $Document['excluded']
    $pending = $Document['pendingApproval']
    $status = [ordered]@{
        groupId              = $Document['groupId']
        lastSyncUtc          = ConvertTo-DgApiTime -Value $Document['lastSyncUtc']
        lastResult           = [string]$Document['lastResult']
        dryRunReason         = $Document['dryRunReason']
        memberCount          = [int]$Document['memberCount']
        added                = [int]$Document['added']
        removed              = [int]$Document['removed']
        skipped              = [int]$Document['skipped']
        excluded             = [ordered]@{
            disabled = if ($excluded) { [int]$excluded['disabled'] } else { 0 }
            guests   = if ($excluded) { [int]$excluded['guests'] } else { 0 }
        }
        warnings             = [string[]]@($Document['warnings'] | Where-Object { $_ })
        lastError            = $Document['lastError']
        lastRunId            = $Document['lastRunId']
        handledSyncRequestAt = ConvertTo-DgApiTime -Value $Document['handledSyncRequestAt']
        pendingApproval      = $null
        compare              = $Document['compare']
    }
    if ($pending) {
        $status.pendingApproval = [ordered]@{
            kind     = $pending['kind']; diffHash = $pending['diffHash']; adds = [int]$pending['adds']; removes = [int]$pending['removes']
            percent  = [double]$pending['percent']
        }
        if ($pending['detectedAt']) { $status.pendingApproval.detectedAt = ConvertTo-DgApiTime -Value $pending['detectedAt'] }
    }
    $status
}
