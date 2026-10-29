function ConvertFrom-DgTimestamp {
    <#
    .SYNOPSIS
        Reads a stored timestamp back. Accepts text, or the DateTime that ConvertFrom-Json makes of
        ISO dates; returns $null for an empty value. A DateTime without a kind counts as UTC.
    .EXAMPLE
        ConvertFrom-DgTimestamp -Value $status['lastSyncUtc']
    #>
    [CmdletBinding()]
    [OutputType([Nullable[DateTimeOffset]])]
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or ($Value -is [string] -and -not $Value)) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTime]) {
        $utc = if ($Value.Kind -eq [DateTimeKind]::Unspecified) { [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc) } else { $Value.ToUniversalTime() }
        return [DateTimeOffset]::new($utc)
    }
    [DateTimeOffset]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
}
