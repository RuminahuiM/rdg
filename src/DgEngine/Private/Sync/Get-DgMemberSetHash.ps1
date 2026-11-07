function Get-DgMemberSetHash {
    <#
    .SYNOPSIS
        SHA-256 of a set of IDs (order and case don't matter), as "sha256:<hex>".
    .DESCRIPTION
        Used for lastWrittenMembersHash (manual-change detection) and, with prefixed entries,
        for the diff hash that an approval refers to (see Get-DgDiffHash).
    .EXAMPLE
        Get-DgMemberSetHash -Ids @('b', 'A')   # same as @('a', 'b')
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Ids
    )

    $lines = [string[]]@($Ids | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique -CaseSensitive)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    'sha256:' + [System.Convert]::ToHexString($hash).ToLowerInvariant()
}
