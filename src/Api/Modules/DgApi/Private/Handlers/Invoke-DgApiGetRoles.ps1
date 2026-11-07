function Invoke-DgApiGetRoles {
    <#
    .SYNOPSIS
        POST /api/roles: the Static Web Apps roles source. Turns the token's roles claim (Entra app
        roles Admin, Reader) into the roles admin and reader. Unknown values are ignored.
    .EXAMPLE
        Invoke-DgApiGetRoles -Request $Request -Caller $null -Context $context
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

    $raw = Get-DgRequestPart -Request $Request -Name 'RawBody'
    $body = Get-DgRequestPart -Request $Request -Name 'Body'
    $principal = try {
        if ($raw) { ConvertFrom-Json -InputObject $raw -AsHashtable -ErrorAction Stop } elseif ($body -is [System.Collections.IDictionary]) { $body } else { @{} }
    } catch { @{} }
    $roles = [System.Collections.Generic.SortedSet[string]]::new()
    foreach ($claim in @($principal['claims'])) {
        if ($claim -isnot [System.Collections.IDictionary]) { continue }
        if ([string]$claim['typ'] -notin @('roles', 'role', 'http://schemas.microsoft.com/ws/2008/06/identity/claims/role')) { continue }
        switch ([string]$claim['val']) {
            'Admin' { [void]$roles.Add('admin') }
            'Reader' { [void]$roles.Add('reader') }
        }
    }
    New-DgApiResponse -Status 200 -Body ([ordered]@{ roles = [string[]]@($roles) })
}
