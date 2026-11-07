function Get-DgDiffHash {
    <#
    .SYNOPSIS
        Identifies a diff exactly: who is added and who is removed.
    .DESCRIPTION
        An approval stores this hash; the engine writes an approved diff only while the hash
        still matches, so an approval never covers a different, possibly bigger change.
    .EXAMPLE
        Get-DgDiffHash -Adds $diff.Adds -Removes $diff.Removes
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Adds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Removes
    )

    $entries = [string[]]@(@($Adds | ForEach-Object { "+$_" }) + @($Removes | ForEach-Object { "-$_" }))
    Get-DgMemberSetHash -Ids $entries
}
