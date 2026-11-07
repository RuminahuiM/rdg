function Get-DgStoreItem {
    <#
    .SYNOPSIS
        Reads one document, or $null if it doesn't exist. The result carries the _etag.
    .EXAMPLE
        Get-DgStoreItem -Store $store -Container state -Id 'lock-Entra' -PartitionKey 'lock'
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Store,

        [Parameter(Mandatory)]
        [ValidateSet('config', 'state', 'runs')]
        [string] $Container,

        [Parameter(Mandatory)]
        [string] $Id,

        [Parameter(Mandatory)]
        [string] $PartitionKey
    )

    if ($Store.Kind -eq 'Memory') {
        $entry = $Store.Containers[$Container]["$PartitionKey|$Id"]
        if (-not $entry) { return $null }
        $document = ConvertFrom-Json -InputObject $entry.Json -AsHashtable
        $document['_etag'] = $entry.ETag
        return $document
    }

    $response = Invoke-DgCosmosRequest -Store $Store -Method GET -PartitionKey $PartitionKey `
        -Path "dbs/$($Store.Database)/colls/$Container/docs/$([System.Uri]::EscapeDataString($Id))"
    switch ([int]$response.StatusCode) {
        200 { return ConvertFrom-Json -InputObject $response.Content -AsHashtable }
        404 { return $null }
        default { throw (Get-DgStoreError -Response $response -Action "reading $Container/$Id") }
    }
}
