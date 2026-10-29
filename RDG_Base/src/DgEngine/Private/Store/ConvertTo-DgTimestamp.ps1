function ConvertTo-DgTimestamp {
    <#
    .SYNOPSIS
        Formats a point in time the way RDG stores it: UTC, ISO 8601, milliseconds, "Z".
    .EXAMPLE
        ConvertTo-DgTimestamp -Value ([DateTimeOffset]::UtcNow)   # 2026-10-12T08:15:00.000Z
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [DateTimeOffset] $Value
    )

    $Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}
