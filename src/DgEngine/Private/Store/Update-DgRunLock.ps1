function Update-DgRunLock {
    <#
    .SYNOPSIS
        Extends the run lock's lease when less than half of it is left, so a long run keeps the
        lock. Throws if the lock was lost (another job took it over), which stops the run.
    .EXAMPLE
        $lock = Update-DgRunLock -Store $store -Lock $lock -Now $now -LeaseMinutes 30
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Store,

        [Parameter(Mandatory)]
        [pscustomobject] $Lock,

        [Parameter(Mandatory)]
        [DateTimeOffset] $Now,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1440)]
        [int] $LeaseMinutes
    )

    $document = $Lock.Lock
    $expires = ConvertFrom-DgTimestamp -Value $document['expiresAt']
    if ($expires -and ($expires - $Now).TotalMinutes -gt $LeaseMinutes / 2) { return $Lock }

    if (-not $PSCmdlet.ShouldProcess([string]$document['id'], 'Extend the lease')) { return $Lock }
    $renewed = [ordered]@{}
    foreach ($key in $document.Keys) { if ($key -notlike '_*') { $renewed[$key] = $document[$key] } }
    $renewed['acquiredAt'] = ConvertTo-DgTimestamp -Value (ConvertFrom-DgTimestamp -Value $document['acquiredAt'])
    $renewed['expiresAt'] = ConvertTo-DgTimestamp -Value $Now.AddMinutes($LeaseMinutes)
    if (-not (Set-DgStoreItem -Store $Store -Container state -Document $renewed -ETag ([string]$document['_etag']))) {
        throw 'the run lock was taken over by another job; this run stops'
    }
    [pscustomobject]@{
        Acquired = $true
        Lock     = Get-DgStoreItem -Store $Store -Container state -Id ([string]$document['id']) -PartitionKey 'lock'
        HeldBy   = $null
    }
}
