function Invoke-DgApiUpdateDefinition {
    <#
    .SYNOPSIS
        PUT /api/definitions/{id}: replaces the fields IT sets, guarded by If-Match, with an audit
        record listing every changed field. Engine-owned fields (status, sync request, approval)
        are kept.
    .EXAMPLE
        Invoke-DgApiUpdateDefinition -Request $Request -Caller $caller -Context $context
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

    $stored = Get-DgStoredDefinition -Context $Context -Id (Get-DgRequestValue -Request $Request -Part Params -Name id)
    $current = $stored.Definition
    $etag = Assert-DgIfMatch -Request $Request -Document $current
    $body = Read-DgRequestBody -Request $Request -Schema DefinitionInput
    $data = Get-DgApiStoreData -Context $Context
    $fields = ConvertFrom-DgDefinitionInput -Context $Context -Body $body -Data $data -Current $current

    $document = [ordered]@{}
    foreach ($key in $current.Keys) { if ($key -notlike '_*') { $document[$key] = $current[$key] } }
    foreach ($key in $fields.Keys) { $document[$key] = $fields[$key] }
    $changes = @(Get-DgChangeList -Old $current -New $document -Fields ([string[]]@($fields.Keys)))
    if ($changes.Count -eq 0) {
        $definition = ConvertTo-DgApiDefinition -Document $current -Status $stored.Status
        return New-DgApiResponse -Status 200 -Body $definition -ETag $definition.etag
    }
    $document.updatedAt = Invoke-DgEngine -Name ConvertTo-DgTimestamp -Parameters @{ Value = (& $Context.Now) }
    $document.updatedBy = $Caller.Upn
    $audit = New-DgAuditDocument -Context $Context -PartitionKey $current['id'] -Action update -By $Caller.Upn -Changes $changes -DefinitionName $fields.name
    Invoke-DgApiBatch -Context $Context -PartitionKey $current['id'] -GuardedId $current['id'] -Operations @(
        @{ Kind = 'Replace'; Document = $document; IfMatch = $etag }
        @{ Kind = 'Create'; Document = $audit }
    )
    $stored = Get-DgStoredDefinition -Context $Context -Id $current['id']
    $definition = ConvertTo-DgApiDefinition -Document $stored.Definition -Status $stored.Status
    New-DgApiResponse -Status 200 -Body $definition -ETag $definition.etag
}
