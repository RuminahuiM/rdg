function Invoke-DgApiGetDefinition {
    <#
    .SYNOPSIS
        GET /api/definitions/{id}: one definition with its status and ETag, plus the names of the
        users and the compare group it references (see Add-DgApiDisplayName).
    .EXAMPLE
        Invoke-DgApiGetDefinition -Request $Request -Caller $caller -Context $context
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

    $stored = Get-DgStoredDefinition -Context $Context -Id (Get-DgRequestValue -Request $Request -Part Params -Name id)
    $definition = ConvertTo-DgApiDefinition -Document $stored.Definition -Status $stored.Status
    $definition = Add-DgApiDisplayName -Definition $definition -Context $Context
    New-DgApiResponse -Status 200 -Body $definition -ETag $definition.etag
}
