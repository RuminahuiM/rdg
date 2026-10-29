function Invoke-DgApiGetSettings {
    <#
    .SYNOPSIS
        GET /api/settings: the organisation settings with their ETag.
    .EXAMPLE
        Invoke-DgApiGetSettings -Request $Request -Caller $caller -Context $context
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Named after the OpenAPI operationId.')]
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

    $document = Get-DgSettingsDocument -Context $Context
    $settings = ConvertTo-DgApiSetting -Document $document
    New-DgApiResponse -Status 200 -Body $settings -ETag $settings.etag
}
