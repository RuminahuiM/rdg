function Get-DgRequestHeader {
    <#
    .SYNOPSIS
        Reads a request header by name, ignoring case; $null if missing.
    .EXAMPLE
        Get-DgRequestHeader -Request $Request -Name 'If-Match'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [Parameter(Mandatory)]
        [string] $Name
    )

    $headers = Get-DgRequestPart -Request $Request -Name 'Headers'
    if (-not $headers) { return $null }
    foreach ($key in $headers.Keys) {
        if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $value = $headers[$key]
            return [string](@($value)[0])
        }
    }
    $null
}
