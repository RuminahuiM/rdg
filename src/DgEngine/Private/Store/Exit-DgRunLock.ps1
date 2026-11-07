function Exit-DgRunLock {
    <#
    .SYNOPSIS
        Releases the run lock, but only if it is still the one this job took (ETag check).
    .EXAMPLE
        Exit-DgRunLock -Store $store -Lock $lock.Lock
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Store,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Lock
    )

    Remove-DgStoreItem -Store $Store -Container state -Id ([string]$Lock['id']) -PartitionKey 'lock' -ETag ([string]$Lock['_etag'])
}
