function Resolve-DgRuleProperty {
    <#
    .SYNOPSIS
        Finds the property map entry for a rule property name, or $null if the name is unknown.
    .DESCRIPTION
        Case-insensitive. Directory extension properties (extension_<32 hex>_<name>) are always
        accepted as text, because they differ per tenant; whether one exists is checked against
        the tenant when the API validates a rule, not here.
    .EXAMPLE
        Resolve-DgRuleProperty -Name 'Department'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $map = Get-DgPropertyMap
    $key = $Name.ToLowerInvariant()
    if ($map.ContainsKey($key)) {
        return $map[$key]
    }
    if ($Name -match '^extension_[0-9a-fA-F]{32}_[A-Za-z0-9_]+$') {
        return New-DgPropertyEntry -Name $Name -Type 'String' -Select $Name -Read 'Direct'
    }
    $null
}
