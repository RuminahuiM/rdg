function Stop-DgPreconditionFailed {
    <#
    .SYNOPSIS
        Ends the request with 412 and the current version: its ETag and who changed it last.
    .EXAMPLE
        Stop-DgPreconditionFailed -Document $current
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only throws; changes no state.')]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Collections.IDictionary] $Document
    )

    $current = [ordered]@{}
    if ($Document) {
        $current.etag = [string]$Document['_etag']
        if ($Document['updatedAt']) { $current.updatedAt = ConvertTo-DgApiTime -Value $Document['updatedAt'] }
        if ($Document['updatedBy']) { $current.updatedBy = [string]$Document['updatedBy'] }
    }
    $who = if ($current.Contains('updatedBy')) { " by $($current.updatedBy)" } else { '' }
    Stop-DgApi -Status 412 -Title 'Changed by someone else' -Detail "the document was changed$who since you loaded it; reload and try again" -Extra @{ current = $current }
}
