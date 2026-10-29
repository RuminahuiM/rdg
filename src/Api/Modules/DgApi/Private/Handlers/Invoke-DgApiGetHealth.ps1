function Invoke-DgApiGetHealth {
    <#
    .SYNOPSIS
        GET /api/health: anonymous deployment check; only the version and "ok", no data.
    .EXAMPLE
        Invoke-DgApiGetHealth -Request $Request -Caller $null -Context $context
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

    New-DgApiResponse -Status 200 -Body ([ordered]@{ status = 'ok'; version = $Context.Version })
}
