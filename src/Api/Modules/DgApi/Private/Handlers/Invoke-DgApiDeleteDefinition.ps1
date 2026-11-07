function Invoke-DgApiDeleteDefinition {
    <#
    .SYNOPSIS
        DELETE /api/definitions/{id}: removes the definition and releases its group unchanged.
        Refused with 409 (and the referencing definitions) when other rules use its group in
        memberOf, unless force=true. Audit history and run records stay until they expire.
    .EXAMPLE
        Invoke-DgApiDeleteDefinition -Request $Request -Caller $caller -Context $context
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
    $id = [string]$current['id']
    $etag = Assert-DgIfMatch -Request $Request -Document $current
    $force = Get-DgRequestValue -Request $Request -Part Query -Name force
    if ($force -and $force -notin @('true', 'false')) { Stop-DgApi -Status 400 -Title 'force must be true or false' -Type 'validation' }

    $groupId = Get-DgDefinitionGroupId -Definition $current -Status $stored.Status
    if ($groupId -and $force -ne 'true') {
        $data = Get-DgApiStoreData -Context $Context
        $referencedBy = foreach ($other in $data.Definitions) {
            if ($other['id'] -eq $id) { continue }
            $check = Test-DgRule -Rule ([string]$other['rule'])
            if (@($check.ReferencedGroupIds | ForEach-Object { $_.ToLowerInvariant() }) -contains $groupId) {
                [ordered]@{ id = $other['id']; name = $other['name'] }
            }
        }
        if (@($referencedBy).Count) {
            Stop-DgApi -Status 409 -Title 'Definition is referenced' -Detail 'other rules use this group in memberOf; they would read it live from now on' -Extra @{ referencedBy = @($referencedBy) }
        }
    }
    $audit = New-DgAuditDocument -Context $Context -PartitionKey $id -Action delete -By $Caller.Upn -DefinitionName ([string]$current['name']) -Changes @(
        [ordered]@{ field = 'definition'; old = [ordered]@{ name = $current['name']; groupType = $current['groupType']; groupId = $groupId; rule = $current['rule'] }; new = $null }
    )
    Invoke-DgApiBatch -Context $Context -PartitionKey $id -GuardedId $id -Operations @(
        @{ Kind = 'Delete'; Id = $id; IfMatch = $etag }
        @{ Kind = 'Create'; Document = $audit }
    )
    # The engine's status goes too; failing here only leaves an orphan the engine ignores.
    try {
        [void](Invoke-DgEngine -Name Remove-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'state'; Id = "status-$id"; PartitionKey = $id; Confirm = $false })
    } catch {
        Write-Warning -Message "status of $id was not removed: $($_.Exception.Message)"
    }
    New-DgApiResponse -Status 204 -Body $null
}
