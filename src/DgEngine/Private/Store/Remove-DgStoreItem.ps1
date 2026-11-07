function Remove-DgStoreItem {
    <#
    .SYNOPSIS
        Deletes a document. A missing document counts as removed. With -ETag it deletes only if
        the stored document still has that ETag and returns $false otherwise.
    .EXAMPLE
        Remove-DgStoreItem -Store $store -Container state -Id 'lock-Entra' -PartitionKey 'lock' -ETag $lock._etag
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
        [string] $Id,

        [Parameter(Mandatory)]
        [string] $PartitionKey,

        [string] $ETag
    )

    if (-not $PSCmdlet.ShouldProcess("$Container/$Id", 'Delete')) { return $false }
    if ($Store.Kind -eq 'Memory') {
        $key = "$PartitionKey|$Id"
        $existing = $Store.Containers[$Container][$key]
        if (-not $existing) { return $true }
        if ($ETag -and $existing.ETag -ne $ETag) { return $false }
        $Store.Containers[$Container].Remove($key)
        return $true
    }

    $headers = @{}
    if ($ETag) { $headers['If-Match'] = $ETag }
    $response = Invoke-DgCosmosRequest -Store $Store -Method DELETE -PartitionKey $PartitionKey -Headers $headers `
        -Path "dbs/$($Store.Database)/colls/$Container/docs/$([System.Uri]::EscapeDataString($Id))"
    switch ([int]$response.StatusCode) {
        { $_ -in @(200, 204, 404) } { return $true }
        412 { return $false }
        default { throw (Get-DgStoreError -Response $response -Action "deleting $Container/$Id") }
    }
}
