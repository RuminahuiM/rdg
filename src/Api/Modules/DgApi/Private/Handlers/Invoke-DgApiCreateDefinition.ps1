function Invoke-DgApiCreateDefinition {
    <#
    .SYNOPSIS
        POST /api/definitions: validates and stores a new definition together with its audit record.
        target.mode adopt starts an adoption (the engine runs dry and waits for approval).
    .EXAMPLE
        Invoke-DgApiCreateDefinition -Request $Request -Caller $caller -Context $context
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [AllowNull()]
        [pscustomobject] $Caller,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $body = Read-DgRequestBody -Request $Request -Schema DefinitionInput
    $data = Get-DgApiStoreData -Context $Context
    $fields = ConvertFrom-DgDefinitionInput -Context $Context -Body $body -Data $data
    $at = & $Context.Now
    $now = Invoke-DgEngine -Name ConvertTo-DgTimestamp -Parameters @{ Value = $at }
    $id = 'def-' + (New-DgUlid -Time $at)
    $document = [ordered]@{ id = $id; pk = $id; type = 'definition'; schemaVersion = 1 }
    foreach ($key in $fields.Keys) { $document[$key] = $fields[$key] }
    $document.syncRequest = $null
    $document.approval = $null
    $document.createdAt = $now
    $document.createdBy = $Caller.Upn
    $document.updatedAt = $now
    $document.updatedBy = $Caller.Upn

    $action = if ($fields.target.mode -eq 'adopt') { 'adopt' } else { 'create' }
    $changes = @(Get-DgChangeList -Old $null -New $document -Fields ([string[]]@($fields.Keys)))
    $audit = New-DgAuditDocument -Context $Context -PartitionKey $id -Action $action -By $Caller.Upn -Changes $changes -DefinitionName $fields.name
    Invoke-DgApiBatch -Context $Context -PartitionKey $id -Operations @(
        @{ Kind = 'Create'; Document = $document }
        @{ Kind = 'Create'; Document = $audit }
    )
    $stored = Get-DgStoredDefinition -Context $Context -Id $id
    $definition = ConvertTo-DgApiDefinition -Document $stored.Definition -Status $stored.Status
    New-DgApiResponse -Status 201 -Body $definition -ETag $definition.etag -Location "/api/definitions/$id"
}
