function Invoke-DgApiBatch {
    <#
    .SYNOPSIS
        Writes a change and its audit record in one transactional batch. A lost race ends with 412
        (current version included), a duplicate with 409.
    .EXAMPLE
        Invoke-DgApiBatch -Context $Context -Container config -PartitionKey $id -Operations $operations
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context,

        [Parameter(Mandatory)]
        [string] $PartitionKey,

        [Parameter(Mandatory)]
        [hashtable[]] $Operations,

        # Document ID to show in a 412 (the one guarded by If-Match).
        [string] $GuardedId
    )

    $result = Invoke-DgEngine -Name Invoke-DgStoreBatch -Parameters @{
        Store = $Context.Store; Container = 'config'; PartitionKey = $PartitionKey; Operations = $Operations; Confirm = $false
    }
    if ($result.Succeeded) { return }
    switch ($result.Status) {
        412 {
            $current = if ($GuardedId) { Invoke-DgEngine -Name Get-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'config'; Id = $GuardedId; PartitionKey = $PartitionKey } } else { $null }
            Stop-DgPreconditionFailed -Document $current
        }
        404 { Stop-DgApi -Status 404 -Title 'Definition not found' }
        409 { Stop-DgApi -Status 409 -Title 'Already exists' }
        default { throw "the batch write failed with status $($result.Status)" }
    }
}
