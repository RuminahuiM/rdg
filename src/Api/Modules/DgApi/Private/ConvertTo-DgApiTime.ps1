function ConvertTo-DgApiTime {
    <#
    .SYNOPSIS
        Formats a stored time for a response (UTC, ISO 8601); $null stays $null. Stored dates may
        come back as text or as DateTime (ConvertFrom-Json turns ISO strings into dates).
    .EXAMPLE
        ConvertTo-DgApiTime -Value $document['updatedAt']
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $Value
    )

    $parsed = Invoke-DgEngine -Name ConvertFrom-DgTimestamp -Parameters @{ Value = $Value }
    if ($null -eq $parsed) { return $null }
    Invoke-DgEngine -Name ConvertTo-DgTimestamp -Parameters @{ Value = $parsed }
}
