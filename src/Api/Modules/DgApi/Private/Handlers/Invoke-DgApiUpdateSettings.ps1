function Invoke-DgApiUpdateSettings {
    <#
    .SYNOPSIS
        PUT /api/settings: replaces the organisation settings, guarded by If-Match, with an audit
        record of the changed fields. Pausing records who paused and when.
    .EXAMPLE
        Invoke-DgApiUpdateSettings -Request $Request -Caller $caller -Context $context
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Named after the OpenAPI operationId.')]
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

    $current = Get-DgSettingsDocument -Context $Context
    $etag = Assert-DgIfMatch -Request $Request -Document $current
    $body = Read-DgRequestBody -Request $Request -Schema SettingsInput
    $document = [ordered]@{}
    foreach ($key in $current.Keys) { if ($key -notlike '_*') { $document[$key] = $current[$key] } }
    $fields = [string[]]@('paused', 'verboseLogging', 'changeLimitPercent', 'changeLimitMinChanges', 'newGroupsDryRun', 'nestedMembers',
        'frequencyOptions', 'naming', 'marker', 'auditRetentionDays')
    foreach ($field in $fields) { $document[$field] = $body[$field] }
    $now = Invoke-DgEngine -Name ConvertTo-DgTimestamp -Parameters @{ Value = (& $Context.Now) }
    if ([bool]$body['paused'] -and -not [bool]$current['paused']) {
        $document.pausedAt = $now
        $document.pausedBy = $Caller.Upn
    } elseif (-not [bool]$body['paused']) {
        $document.pausedAt = $null
        $document.pausedBy = $null
    }
    $changes = @(Get-DgChangeList -Old $current -New $document -Fields $fields)
    if ($changes.Count -eq 0) {
        $settings = ConvertTo-DgApiSetting -Document $current
        return New-DgApiResponse -Status 200 -Body $settings -ETag $settings.etag
    }
    $document.updatedAt = $now
    $document.updatedBy = $Caller.Upn
    $audit = New-DgAuditDocument -Context $Context -PartitionKey 'settings' -Action settings -By $Caller.Upn -Changes $changes
    Invoke-DgApiBatch -Context $Context -PartitionKey 'settings' -GuardedId 'settings' -Operations @(
        @{ Kind = 'Replace'; Document = $document; IfMatch = $etag }
        @{ Kind = 'Create'; Document = $audit }
    )
    $settings = ConvertTo-DgApiSetting -Document (Get-DgSettingsDocument -Context $Context)
    New-DgApiResponse -Status 200 -Body $settings -ETag $settings.etag
}
