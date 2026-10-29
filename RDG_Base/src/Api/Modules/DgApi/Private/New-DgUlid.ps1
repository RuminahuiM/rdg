function New-DgUlid {
    <#
    .SYNOPSIS
        A new ULID: 26 Crockford base32 characters, 48 bits of milliseconds then 80 random bits,
        so IDs sort by creation time.
    .EXAMPLE
        'def-' + (New-DgUlid)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory value only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Nullable[DateTimeOffset]] $Time
    )

    $alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
    $at = if ($null -ne $Time) { [DateTimeOffset]$Time } else { [DateTimeOffset]::UtcNow }
    $milliseconds = [System.Numerics.BigInteger]$at.ToUnixTimeMilliseconds()
    $random = [byte[]]::new(10)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($random)
    $value = $milliseconds
    foreach ($byte in $random) { $value = ($value * 256) + $byte }
    $chars = [char[]]::new(26)
    for ($i = 25; $i -ge 0; $i--) {
        $chars[$i] = $alphabet[[int]($value % 32)]
        $value = $value / 32
    }
    -join $chars
}
