function Find-DgStoreItem {
    <#
    .SYNOPSIS
        Returns all documents of one type in a container (across partitions), following continuation pages.
    .EXAMPLE
        Find-DgStoreItem -Store $store -Container config -Type definition
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Store,

        [Parameter(Mandatory)]
        [ValidateSet('config', 'state', 'runs')]
        [string] $Container,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z]+$')]
        [string] $Type
    )

    $items = [System.Collections.Generic.List[object]]::new()
    if ($Store.Kind -eq 'Memory') {
        foreach ($entry in $Store.Containers[$Container].Values) {
            $document = ConvertFrom-Json -InputObject $entry.Json -AsHashtable
            if ($document['type'] -ne $Type) { continue }
            $document['_etag'] = $entry.ETag
            $items.Add($document)
        }
        return , $items.ToArray()
    }

    $body = ConvertTo-Json -Compress -Depth 5 -InputObject @{
        query      = 'SELECT * FROM c WHERE c.type = @type'
        parameters = @(@{ name = '@type'; value = $Type })
    }
    $continuation = $null
    do {
        $headers = @{
            'Content-Type'                               = 'application/query+json'
            'x-ms-documentdb-isquery'                    = 'True'
            'x-ms-documentdb-query-enablecrosspartition' = 'True'
            'x-ms-max-item-count'                        = '1000'
        }
        if ($continuation) { $headers['x-ms-continuation'] = $continuation }
        $response = Invoke-DgCosmosRequest -Store $Store -Method POST -Path "dbs/$($Store.Database)/colls/$Container/docs" -Headers $headers -Body $body
        if ([int]$response.StatusCode -ne 200) { throw (Get-DgStoreError -Response $response -Action "listing $Type documents") }
        $page = ConvertFrom-Json -InputObject $response.Content -AsHashtable
        foreach ($document in @($page['Documents'])) { if ($null -ne $document) { $items.Add($document) } }
        $continuation = if ($response.Headers) { [string]$response.Headers['x-ms-continuation'] } else { '' }
    } while ($continuation)
    , $items.ToArray()
}
