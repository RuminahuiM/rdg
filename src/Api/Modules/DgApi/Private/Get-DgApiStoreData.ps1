function Get-DgApiStoreData {
    <#
    .SYNOPSIS
        Reads all definitions and the engine's status documents (status by definition ID), for
        lists, group-link checks and memberOf lookups.
    .EXAMPLE
        $data = Get-DgApiStoreData -Context $Context
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $definitions = Invoke-DgEngine -Name Find-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'config'; Type = 'definition' }
    $statuses = @{}
    foreach ($status in (Invoke-DgEngine -Name Find-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'state'; Type = 'status' })) {
        $statuses[[string]$status['pk']] = $status
    }
    [pscustomobject]@{
        Definitions = [object[]]@($definitions)
        Statuses    = $statuses
    }
}
