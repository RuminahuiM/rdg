function Invoke-DgApiSyncDefinition {
    <#
    .SYNOPSIS
        POST /api/definitions/{id}/sync: records a sync request (with audit) and starts a SyncNow
        job of the matching runbook.
    .DESCRIPTION
        The request stays on the definition, so if the job can't start the next scheduled run
        handles it (jobStarted = false). A request from the last minute that hasn't been handled
        is returned instead of starting another job. Read-only installations refuse sync of a
        group RDG would create or adopt (409).
    .EXAMPLE
        Invoke-DgApiSyncDefinition -Request $Request -Caller $caller -Context $context
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [AllowNull()]
        [pscustomobject] $Caller,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $id = Get-DgRequestValue -Request $Request -Part Params -Name id
    $at = & $Context.Now
    $requestedText = Invoke-DgEngine -Name ConvertTo-DgTimestamp -Parameters @{ Value = $at }
    for ($attempt = 1; ; $attempt++) {
        $stored = Get-DgStoredDefinition -Context $Context -Id $id
        $current = $stored.Definition
        $mode = [string]$current['target']['mode']
        if ($Context.AccessMode -eq 'read-only' -and $mode -in @('create', 'adopt')) {
            $verb = if ($mode -eq 'create') { 'create' } else { 'adopt' }
            Stop-DgApi -Status 409 -Title 'Read-only installation' -Detail "a read-only installation can't $verb groups"
        }
        $request = $current['syncRequest']
        if ($request) {
            $requestedAt = Invoke-DgEngine -Name ConvertFrom-DgTimestamp -Parameters @{ Value = $request['at'] }
            $handled = if ($stored.Status) { Invoke-DgEngine -Name ConvertFrom-DgTimestamp -Parameters @{ Value = $stored.Status['handledSyncRequestAt'] } } else { $null }
            $pending = -not $handled -or $handled -lt $requestedAt
            if ($pending -and ($at - $requestedAt).TotalSeconds -lt 60) {
                return New-DgApiResponse -Status 202 -Body ([ordered]@{
                        requestedAt     = ConvertTo-DgApiTime -Value $request['at']
                        jobStarted      = $false
                        existingRequest = $true
                        message         = "a sync was requested by $($request['by']) less than a minute ago"
                    })
            }
        }
        $document = [ordered]@{}
        foreach ($key in $current.Keys) { if ($key -notlike '_*') { $document[$key] = $current[$key] } }
        $document.syncRequest = [ordered]@{ at = $requestedText; by = $Caller.Upn }
        $changes = @(Get-DgChangeList -Old $current -New $document -Fields @('syncRequest'))
        $audit = New-DgAuditDocument -Context $Context -PartitionKey $id -Action syncNow -By $Caller.Upn -DefinitionName ([string]$current['name']) -Changes $changes
        try {
            Invoke-DgApiBatch -Context $Context -PartitionKey $id -GuardedId $id -Operations @(
                @{ Kind = 'Replace'; Document = $document; IfMatch = [string]$current['_etag'] }
                @{ Kind = 'Create'; Document = $audit }
            )
            break
        } catch {
            # Someone saved the definition meanwhile: read it again once.
            $problem = $_.Exception.Data['DgProblem']
            if ($attempt -ge 2 -or -not $problem -or $problem.status -ne 412) { throw }
        }
    }

    $runbook = if ($current['groupType'] -in @('Security', 'Microsoft365')) { 'Sync-EntraGroups' } else { 'Sync-ExchangeGroups' }
    $accepted = [ordered]@{ requestedAt = $requestedText; jobStarted = $false }
    try {
        $jobId = Start-DgRunbookJob -Context $Context -Runbook $runbook -Parameters @{ Mode = 'SyncNow'; DefinitionId = $id }
        $accepted.jobStarted = $true
        $accepted.jobId = $jobId
    } catch {
        Write-Warning -Message "starting $runbook for $id failed: $($_.Exception.Message)"
        $accepted.message = 'the sync job could not be started; the next scheduled run handles the request'
    }
    New-DgApiResponse -Status 202 -Body $accepted
}
