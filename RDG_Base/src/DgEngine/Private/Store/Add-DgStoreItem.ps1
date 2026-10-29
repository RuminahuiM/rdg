function Add-DgStoreItem {
    <#
    .SYNOPSIS
        Creates a document only if no document with that id and partition key exists.
        Returns $true when created, $false when it already existed.
    .EXAMPLE
        Add-DgStoreItem -Store $store -Container state -Document $lock
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
        [System.Collections.IDictionary] $Document
    )

    if (-not $PSCmdlet.ShouldProcess("$Container/$($Document['id'])", 'Create')) { return $false }
    $json = ConvertTo-Json -InputObject $Document -Depth 20 -Compress
    if ($Store.Kind -eq 'Memory') {
        $key = "$($Document['pk'])|$($Document['id'])"
        if ($Store.Containers[$Container].Contains($key)) { return $false }
        $Store.Version++
        $Store.Containers[$Container][$key] = @{ Json = $json; ETag = "`"$($Store.Version)`"" }
        return $true
    }

    $response = Invoke-DgCosmosRequest -Store $Store -Method POST -Path "dbs/$($Store.Database)/colls/$Container/docs" `
        -PartitionKey ([string]$Document['pk']) -Body $json
    switch ([int]$response.StatusCode) {
        201 { return $true }
        409 { return $false }
        default { throw (Get-DgStoreError -Response $response -Action "creating $Container/$($Document['id'])") }
    }
}
