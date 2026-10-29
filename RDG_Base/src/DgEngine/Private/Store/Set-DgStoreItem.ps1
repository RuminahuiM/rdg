function Set-DgStoreItem {
    <#
    .SYNOPSIS
        Writes a document. Without -ETag it creates or overwrites (upsert). With -ETag it replaces
        only if the stored document still has that ETag; returns $false if someone changed it.
    .EXAMPLE
        Set-DgStoreItem -Store $store -Container state -Document $status
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Store,

        [Parameter(Mandatory)]
        [ValidateSet('config', 'state', 'runs')]
        [string] $Container,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document,

        [string] $ETag
    )

    if (-not $PSCmdlet.ShouldProcess("$Container/$($Document['id'])", 'Write')) { return $false }
    $clean = [ordered]@{}
    foreach ($key in $Document.Keys) {
        if ($key -notin @('_rid', '_self', '_etag', '_attachments', '_ts')) { $clean[$key] = $Document[$key] }
    }
    $json = ConvertTo-Json -InputObject $clean -Depth 20 -Compress
    $id = [string]$Document['id']
    $pk = [string]$Document['pk']

    if ($Store.Kind -eq 'Memory') {
        $key = "$pk|$id"
        $existing = $Store.Containers[$Container][$key]
        if ($ETag -and (-not $existing -or $existing.ETag -ne $ETag)) { return $false }
        $Store.Version++
        $Store.Containers[$Container][$key] = @{ Json = $json; ETag = "`"$($Store.Version)`"" }
        return $true
    }

    if ($ETag) {
        $response = Invoke-DgCosmosRequest -Store $Store -Method PUT -PartitionKey $pk -Body $json -Headers @{ 'If-Match' = $ETag } `
            -Path "dbs/$($Store.Database)/colls/$Container/docs/$([System.Uri]::EscapeDataString($id))"
    } else {
        $response = Invoke-DgCosmosRequest -Store $Store -Method POST -PartitionKey $pk -Body $json -Headers @{ 'x-ms-documentdb-is-upsert' = 'True' } `
            -Path "dbs/$($Store.Database)/colls/$Container/docs"
    }
    switch ([int]$response.StatusCode) {
        { $_ -in @(200, 201) } { return $true }
        { $_ -in @(404, 412) -and $ETag } { return $false }
        default { throw (Get-DgStoreError -Response $response -Action "writing $Container/$id") }
    }
}
