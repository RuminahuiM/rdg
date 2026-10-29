function Enter-DgRunLock {
    <#
    .SYNOPSIS
        Takes the run lock of one runbook (Entra or Exchange), or reports who holds it.
    .DESCRIPTION
        The lock is a document in the state container with a lease (expiresAt). A free lock is
        created; an expired one is replaced with If-Match, so two jobs racing for it can't both
        win. Returns Acquired, Lock (the stored document with its ETag) and HeldBy (job ID of
        the holder when not acquired).
    .EXAMPLE
        $lock = Enter-DgRunLock -Store $store -Provider Entra -JobId $jobId -Now $now -LeaseMinutes 6
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
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
        [ValidateRange(1, 1440)]
        [int] $LeaseMinutes
    )

    $id = "lock-$Provider"
    $document = [ordered]@{
        id            = $id
        pk            = 'lock'
        type          = 'lock'
        schemaVersion = 1
        jobId         = $JobId
        acquiredAt    = ConvertTo-DgTimestamp -Value $Now
        expiresAt     = ConvertTo-DgTimestamp -Value $Now.AddMinutes($LeaseMinutes)
    }
    $result = { param($acquired, $heldBy) [pscustomobject]@{ Acquired = $acquired; Lock = if ($acquired) { Get-DgStoreItem -Store $Store -Container state -Id $id -PartitionKey 'lock' } else { $null }; HeldBy = $heldBy } }

    $existing = Get-DgStoreItem -Store $Store -Container state -Id $id -PartitionKey 'lock'
    if (-not $existing) {
        if (Add-DgStoreItem -Store $Store -Container state -Document $document) { return & $result $true $null }
        $existing = Get-DgStoreItem -Store $Store -Container state -Id $id -PartitionKey 'lock'
        if (-not $existing) { return & $result $false 'unknown' }
    }
    $expires = ConvertFrom-DgTimestamp -Value $existing['expiresAt']
    if ($expires -and $expires -gt $Now) {
        return & $result $false ([string]$existing['jobId'])
    }
    if (Set-DgStoreItem -Store $Store -Container state -Document $document -ETag ([string]$existing['_etag'])) {
        return & $result $true $null
    }
    & $result $false 'unknown'
}
