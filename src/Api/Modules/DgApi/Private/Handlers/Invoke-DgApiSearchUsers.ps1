function Invoke-DgApiSearchUsers {
    <#
    .SYNOPSIS
        GET /api/directory/users?search=: people picker, up to 25 users by prefix.
    .EXAMPLE
        Invoke-DgApiSearchUsers -Request $Request -Caller $caller -Context $context
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

    $search = Get-DgSearchText -Request $Request
    $graph = Get-DgApiGraph -Context $Context
    $found = Invoke-DgEngine -Name Find-DgDirectoryObject -Parameters @{ Directory = $graph; Kind = 'User'; Search = $search }
    $items = foreach ($user in $found) {
        $field = { param([string] $Name) Invoke-DgEngine -Name Get-DgFieldValue -Parameters @{ Object = $user; Name = $Name } }
        $userType = [string](& $field 'userType')
        $mail = [string](& $field 'mail')
        [ordered]@{
            id             = [string](& $field 'id')
            upn            = [string](& $field 'userPrincipalName')
            displayName    = [string](& $field 'displayName')
            mail           = if ($mail) { $mail } else { $null }
            accountEnabled = [bool](& $field 'accountEnabled')
            userType       = if ($userType -eq 'Guest') { 'Guest' } else { 'Member' }
        }
    }
    New-DgApiResponse -Status 200 -Body ([ordered]@{ items = [object[]]@($items) })
}
