function New-DgDefaultSettingDocument {
    <#
    .SYNOPSIS
        The settings document of a new installation, with the documented defaults.
    .DESCRIPTION
        The API creates it on first use (it is the only identity that writes the config
        container); until then the engine works with the same defaults in memory.
    .EXAMPLE
        $document = New-DgDefaultSettingDocument
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object, changes nothing.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    [ordered]@{
        id                    = 'settings'
        pk                    = 'settings'
        type                  = 'settings'
        schemaVersion         = 1
        paused                = $false
        pausedAt              = $null
        pausedBy              = $null
        verboseLogging        = $false
        changeLimitPercent    = 50
        changeLimitMinChanges = 10
        newGroupsDryRun       = $true
        nestedMembers         = $true
        frequencyOptions      = @(15, 30, 60, 360, 1440)
        naming                = [ordered]@{
            prefix = [ordered]@{ enabled = $false; text = '' }
            suffix = [ordered]@{ enabled = $false; text = '' }
        }
        marker                = [ordered]@{ enabled = $false; exchangeCustomAttribute = 15 }
        auditRetentionDays    = 60
        updatedAt             = $null
        updatedBy             = $null
    }
}
