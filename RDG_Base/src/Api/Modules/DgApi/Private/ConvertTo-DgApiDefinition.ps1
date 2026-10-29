function ConvertTo-DgApiDefinition {
    <#
    .SYNOPSIS
        Maps a stored definition plus the engine's status to the API's Definition object.
        For target mode create, the group ID the engine stored in the status is shown in target.
    .EXAMPLE
        ConvertTo-DgApiDefinition -Document $definition -Status $status
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document,

        [AllowNull()]
        [System.Collections.IDictionary] $Status
    )

    $target = [ordered]@{}
    foreach ($key in $Document['target'].Keys) { $target[$key] = $Document['target'][$key] }
    if ($target['mode'] -eq 'create' -and $Status -and $Status['groupId']) { $target['groupId'] = $Status['groupId'] }
    $syncRequest = $Document['syncRequest']
    $approval = $Document['approval']

    [ordered]@{
        id                 = $Document['id']
        etag               = [string]$Document['_etag']
        name               = $Document['name']
        groupType          = $Document['groupType']
        target             = $target
        rule               = $Document['rule']
        includeUserIds     = [string[]]@($Document['includeUserIds'] | Where-Object { $_ })
        excludeUserIds     = [string[]]@($Document['excludeUserIds'] | Where-Object { $_ })
        includeDisabled    = [bool]$Document['includeDisabled']
        includeGuests      = [bool]$Document['includeGuests']
        frequencyMinutes   = [int]$Document['frequencyMinutes']
        enabled            = [bool]$Document['enabled']
        dryRun             = [bool]$Document['dryRun']
        changeLimitPercent = $Document['changeLimitPercent']
        allowEmpty         = [bool]$Document['allowEmpty']
        compareGroupId     = $Document['compareGroupId']
        createdAt          = ConvertTo-DgApiTime -Value $Document['createdAt']
        createdBy          = $Document['createdBy']
        updatedAt          = ConvertTo-DgApiTime -Value $Document['updatedAt']
        updatedBy          = $Document['updatedBy']
        syncRequest        = if ($syncRequest) { [ordered]@{ at = ConvertTo-DgApiTime -Value $syncRequest['at']; by = $syncRequest['by'] } } else { $null }
        approval           = if ($approval) {
            [ordered]@{
                kind = $approval['kind']; diffHash = $approval['diffHash']; adds = [int]$approval['adds']; removes = [int]$approval['removes']
                by = $approval['by']; at = ConvertTo-DgApiTime -Value $approval['at']
            }
        } else { $null }
        status             = ConvertTo-DgApiStatus -Document $Status
    }
}
