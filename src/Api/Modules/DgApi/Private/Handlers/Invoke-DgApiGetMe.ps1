function Invoke-DgApiGetMe {
    <#
    .SYNOPSIS
        GET /api/me: the signed-in user, roles, access mode and version.
    .EXAMPLE
        Invoke-DgApiGetMe -Request $Request -Caller $caller -Context $context
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

    New-DgApiResponse -Status 200 -Body ([ordered]@{
            upn        = $Caller.Upn
            roles      = [string[]]@($Caller.Roles)
            accessMode = $Context.AccessMode
            version    = $Context.Version
        })
}
