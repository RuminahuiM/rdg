function Invoke-DgApiListAudit {
    <#
    .SYNOPSIS
        GET /api/audit: change history, newest first, filtered by definition, person and time.
    .EXAMPLE
        Invoke-DgApiListAudit -Request $Request -Caller $caller -Context $context
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Common handler signature.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [AllowNull()]
        [pscustomobject] $Caller,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $definitionId = Get-DgRequestValue -Request $Request -Part Query -Name definitionId
    $by = Get-DgRequestValue -Request $Request -Part Query -Name by
    if ($definitionId -and $definitionId -notmatch '^def-[0-9A-HJKMNP-TV-Z]{26}$') { Stop-DgApi -Status 400 -Title 'definitionId is not a definition ID' -Type 'validation' }
    if ($by -and $by.Length -gt 256) { Stop-DgApi -Status 400 -Title 'by is too long' -Type 'validation' }
    $range = @{}
    foreach ($name in @('from', 'to')) {
        $text = Get-DgRequestValue -Request $Request -Part Query -Name $name
        if (-not $text) { continue }
        $parsed = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
            Stop-DgApi -Status 400 -Title "$name must be an ISO 8601 time" -Type 'validation'
        }
        $range[$name] = $parsed
    }
    $entries = foreach ($audit in (Invoke-DgEngine -Name Find-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'config'; Type = 'audit' })) {
        if ($definitionId -and $audit['pk'] -ne $definitionId) { continue }
        if ($by -and -not [string]::Equals([string]$audit['by'], $by, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $at = Invoke-DgEngine -Name ConvertFrom-DgTimestamp -Parameters @{ Value = $audit['at'] }
        if ($range.ContainsKey('from') -and $at -lt $range.from) { continue }
        if ($range.ContainsKey('to') -and $at -gt $range.to) { continue }
        ConvertTo-DgApiAudit -Document $audit
    }
    $sorted = [object[]]@($entries | Sort-Object -Property { [string]$_.at }, { [string]$_.id } -Descending)
    New-DgApiResponse -Status 200 -Body (Select-DgPage -Items $sorted -Token (Get-DgRequestValue -Request $Request -Part Query -Name continuationToken))
}
