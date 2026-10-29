function ConvertTo-DgApiSetting {
    <#
    .SYNOPSIS
        Maps the settings document to the API's Settings object.
    .EXAMPLE
        ConvertTo-DgApiSetting -Document $settings
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document
    )

    $settings = [ordered]@{ etag = [string]$Document['_etag'] }
    foreach ($key in @('paused', 'verboseLogging', 'changeLimitPercent', 'changeLimitMinChanges', 'newGroupsDryRun', 'nestedMembers',
            'frequencyOptions', 'naming', 'marker', 'auditRetentionDays', 'pausedBy', 'updatedBy')) {
        $settings[$key] = $Document[$key]
    }
    $settings['frequencyOptions'] = [int[]]@($Document['frequencyOptions'])
    $settings['pausedAt'] = ConvertTo-DgApiTime -Value $Document['pausedAt']
    $settings['updatedAt'] = ConvertTo-DgApiTime -Value $Document['updatedAt']
    $settings
}
