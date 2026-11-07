function ConvertTo-DgSetting {
    <#
    .SYNOPSIS
        Turns the settings document into the fields the engine uses, with the documented
        defaults for anything missing.
    .EXAMPLE
        $settings = ConvertTo-DgSetting -Document (Get-DgStoreItem -Store $store -Container config -Id settings -PartitionKey settings)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document
    )

    $value = {
        param($object, [string] $name, $default)
        $found = if ($object) { Get-DgFieldValue -Object $object -Name $name } else { $null }
        if ($null -eq $found) { $default } else { $found }
    }
    $naming = & $value $Document 'naming' $null
    $affix = {
        param([string] $name)
        $part = & $value $naming $name $null
        if ($part -and (& $value $part 'enabled' $false)) { [string](& $value $part 'text' '') } else { '' }
    }
    $marker = & $value $Document 'marker' $null

    [pscustomobject]@{
        PSTypeName              = 'Dg.Settings'
        Paused                  = [bool](& $value $Document 'paused' $false)
        ChangeLimitPercent      = [int](& $value $Document 'changeLimitPercent' 50)
        ChangeLimitMinChanges   = [int](& $value $Document 'changeLimitMinChanges' 10)
        NewGroupsDryRun         = [bool](& $value $Document 'newGroupsDryRun' $true)
        NestedMembers           = [bool](& $value $Document 'nestedMembers' $true)
        Prefix                  = & $affix 'prefix'
        Suffix                  = & $affix 'suffix'
        MarkerEnabled           = [bool](& $value $marker 'enabled' $false)
        ExchangeCustomAttribute = [int](& $value $marker 'exchangeCustomAttribute' 0)
    }
}
