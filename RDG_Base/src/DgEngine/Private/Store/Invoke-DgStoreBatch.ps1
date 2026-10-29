function Invoke-DgStoreBatch {
    <#
    .SYNOPSIS
        Writes several documents of one partition atomically (Cosmos DB transactional batch):
        either every operation succeeds or none does.
    .DESCRIPTION
        Operations: hashtables with Kind (Create, Replace, Upsert, Delete), Document (for Create,
        Replace, Upsert), Id (for Delete) and an optional IfMatch ETag (Replace, Delete).
        Returns Succeeded, Status (HTTP status of the failing operation: 409 create conflict,
        412 ETag mismatch, 404 missing) and FailedIndex. Other failures throw.
        Used by the API to write a change together with its audit record.
    .EXAMPLE
        Invoke-DgStoreBatch -Store $store -Container config -PartitionKey $id -Operations @(
            @{ Kind = 'Replace'; Document = $definition; IfMatch = $etag }
            @{ Kind = 'Create'; Document = $audit })
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Store,

        [Parameter(Mandatory)]
        [ValidateSet('config', 'state', 'runs')]
        [string] $Container,

        [Parameter(Mandatory)]
        [string] $PartitionKey,

        [Parameter(Mandatory)]
        [ValidateCount(1, 100)]
        [hashtable[]] $Operations
    )

    $result = { param([bool] $ok, [int] $status, [int] $index) [pscustomobject]@{ Succeeded = $ok; Status = $status; FailedIndex = $index } }
    $clean = {
        param($document)
        $copy = [ordered]@{}
        foreach ($key in $document.Keys) { if ($key -notin @('_rid', '_self', '_etag', '_attachments', '_ts')) { $copy[$key] = $document[$key] } }
        if ([string]$copy['pk'] -ne $PartitionKey) { throw "batch document $($copy['id']) is not in partition $PartitionKey" }
        $copy
    }
    if (-not $PSCmdlet.ShouldProcess("$Container/$PartitionKey", "Batch of $($Operations.Count)")) { return & $result $false 0 -1 }

    if ($Store.Kind -eq 'Memory') {
        $entries = $Store.Containers[$Container]
        # Check every precondition against a working view first, then apply all at once.
        $view = @{}
        foreach ($key in $entries.Keys) { $view[$key] = $entries[$key] }
        for ($i = 0; $i -lt $Operations.Count; $i++) {
            $operation = $Operations[$i]
            $id = if ($operation['Kind'] -eq 'Delete') { [string]$operation['Id'] } else { [string]$operation['Document']['id'] }
            $key = "$PartitionKey|$id"
            $existing = $view[$key]
            switch ($operation['Kind']) {
                'Create' { if ($existing) { return & $result $false 409 $i } }
                { $_ -in @('Replace', 'Delete') } {
                    if (-not $existing) { return & $result $false 404 $i }
                    if ($operation['IfMatch'] -and $existing.ETag -ne $operation['IfMatch']) { return & $result $false 412 $i }
                }
            }
            if ($operation['Kind'] -eq 'Delete') { $view.Remove($key) } else { $view[$key] = @{ Pending = $true } }
        }
        foreach ($operation in $Operations) {
            if ($operation['Kind'] -eq 'Delete') {
                $entries.Remove("$PartitionKey|$($operation['Id'])")
                continue
            }
            $document = & $clean $operation['Document']
            $Store.Version++
            $entries["$PartitionKey|$($document['id'])"] = @{ Json = (ConvertTo-Json -InputObject $document -Depth 20 -Compress); ETag = "`"$($Store.Version)`"" }
        }
        return & $result $true 200 -1
    }

    $body = @(foreach ($operation in $Operations) {
            $entry = [ordered]@{ operationType = $operation['Kind'] }
            if ($operation['Kind'] -eq 'Delete') {
                $entry.id = [string]$operation['Id']
            } else {
                $document = & $clean $operation['Document']
                if ($operation['Kind'] -eq 'Replace') { $entry.id = [string]$document['id'] }
                $entry.resourceBody = $document
            }
            if ($operation['IfMatch']) { $entry.ifMatch = [string]$operation['IfMatch'] }
            $entry
        })
    $headers = @{
        'x-ms-cosmos-is-batch-request'        = 'True'
        'x-ms-cosmos-batch-atomic'            = 'True'
        'x-ms-cosmos-batch-continue-on-error' = 'False'
    }
    $response = Invoke-DgCosmosRequest -Store $Store -Method POST -Path "dbs/$($Store.Database)/colls/$Container/docs" `
        -PartitionKey $PartitionKey -Headers $headers -Body (ConvertTo-Json -InputObject $body -Depth 20 -Compress)
    $status = [int]$response.StatusCode
    if ($status -eq 200) { return & $result $true 200 -1 }
    # A failed atomic batch reports each operation: the failing one with its own status, the others 424.
    $results = try { @(ConvertFrom-Json -InputObject $response.Content -AsHashtable) } catch { @() }
    for ($i = 0; $i -lt $results.Count; $i++) {
        $code = [int]$results[$i]['statusCode']
        if ($code -ge 400 -and $code -ne 424) {
            if ($code -in @(404, 409, 412)) { return & $result $false $code $i }
            break
        }
    }
    if ($status -in @(404, 409, 412)) { return & $result $false $status -1 }
    throw (Get-DgStoreError -Response $response -Action "writing a batch to $Container/$PartitionKey")
}
