function Get-DgRequestValue {
    <#
    .SYNOPSIS
        Reads a query string or route parameter by name, ignoring case; $null if missing.
    .EXAMPLE
        Get-DgRequestValue -Request $Request -Part Params -Name id
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [Parameter(Mandatory)]
        [ValidateSet('Query', 'Params')]
        [string] $Part,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $values = Get-DgRequestPart -Request $Request -Name $Part
    if (-not $values) { return $null }
    foreach ($key in $values.Keys) {
        if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $value = [string]$values[$key]
            if ($value -eq '') { return $null }
            return $value
        }
    }
    $null
}
