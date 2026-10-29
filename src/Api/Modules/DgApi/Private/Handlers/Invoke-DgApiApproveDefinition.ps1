function Invoke-DgApiApproveDefinition {
    <#
    .SYNOPSIS
        POST /api/definitions/{id}/approve: approves exactly the pending diff (change limit or
        adoption). For an adoption it also marks the group as adopted. Refused with 409 when
        nothing waits, the kind or hash doesn't match, or the installation is read-only.
    .EXAMPLE
        Invoke-DgApiApproveDefinition -Request $Request -Caller $caller -Context $context
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

    $body = Read-DgRequestBody -Request $Request -Schema ApprovalInput
    $stored = Get-DgStoredDefinition -Context $Context -Id (Get-DgRequestValue -Request $Request -Part Params -Name id)
    $current = $stored.Definition
    $id = [string]$current['id']
    if ($Context.AccessMode -eq 'read-only') {
        Stop-DgApi -Status 409 -Title 'Read-only installation' -Detail "a read-only installation doesn't apply changes, so there is nothing to approve"
    }
    $pending = if ($stored.Status) { $stored.Status['pendingApproval'] } else { $null }
    if (-not $pending) { Stop-DgApi -Status 409 -Title 'Nothing to approve' -Detail 'the last run is not waiting for an approval' }
    if ([string]$pending['kind'] -ne [string]$body['kind'] -or [string]$pending['diffHash'] -ne [string]$body['diffHash']) {
        Stop-DgApi -Status 409 -Title 'Approval no longer matches' -Detail 'the pending change differs from the one you saw; load the definition again'
    }

    $document = [ordered]@{}
    foreach ($key in $current.Keys) { if ($key -notlike '_*') { $document[$key] = $current[$key] } }
    $now = Invoke-DgEngine -Name ConvertTo-DgTimestamp -Parameters @{ Value = (& $Context.Now) }
    $document.approval = [ordered]@{
        kind = [string]$pending['kind']; diffHash = [string]$pending['diffHash']; adds = [int]$pending['adds']; removes = [int]$pending['removes']
        by = $Caller.Upn; at = $now
    }
    $fields = @('approval')
    if ($pending['kind'] -eq 'adopt') {
        $target = [ordered]@{}
        foreach ($key in $current['target'].Keys) { $target[$key] = $current['target'][$key] }
        $target.adopted = $true
        $document.target = $target
        $fields += 'target'
    }
    $changes = @(Get-DgChangeList -Old $current -New $document -Fields $fields)
    $audit = New-DgAuditDocument -Context $Context -PartitionKey $id -Action approve -By $Caller.Upn -DefinitionName ([string]$current['name']) -Changes $changes
    Invoke-DgApiBatch -Context $Context -PartitionKey $id -GuardedId $id -Operations @(
        @{ Kind = 'Replace'; Document = $document; IfMatch = [string]$current['_etag'] }
        @{ Kind = 'Create'; Document = $audit }
    )
    $stored = Get-DgStoredDefinition -Context $Context -Id $id
    $definition = ConvertTo-DgApiDefinition -Document $stored.Definition -Status $stored.Status
    New-DgApiResponse -Status 200 -Body $definition -ETag $definition.etag
}
