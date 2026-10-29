function Get-DgFieldValue {
    <#
    .SYNOPSIS
        Reads one field from a hashtable or an object; $null when it isn't there.
    .DESCRIPTION
        Names must use Graph's spelling (the property map does that), except directory extension
        properties, which are matched ignoring case.
    .EXAMPLE
        Get-DgFieldValue -Object $user -Name 'department'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [AllowNull()]
        [object] $Object,

        [AllowNull()]
        [string] $Name
    )

    if ($null -eq $Object -or [string]::IsNullOrEmpty($Name)) {
        return $null
    }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return , $Object[$Name]
        }
        # Graph returns case-sensitive keys. Directory extension names are written by people in
        # rules, so their case may differ from Graph's; look those up ignoring case.
        if ($Name.StartsWith('extension_', [System.StringComparison]::OrdinalIgnoreCase)) {
            foreach ($key in $Object.Keys) {
                if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return , $Object[$key]
                }
            }
        }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return , $property.Value
    }
    $null
}
