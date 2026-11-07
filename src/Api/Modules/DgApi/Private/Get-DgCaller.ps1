function Get-DgCaller {
    <#
    .SYNOPSIS
        Reads the signed-in user from the x-ms-client-principal header the Static Web App adds
        (Base64 JSON with userDetails and userRoles). No or unreadable header ends with 401.
    .DESCRIPTION
        The header can be trusted because the linked Function App only accepts calls that come
        through the Static Web App. Roles are the app roles admin and reader that the roles
        function (POST /api/roles) assigned at sign-in.
    .EXAMPLE
        $caller = Get-DgCaller -Request $Request
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Request
    )

    $header = Get-DgRequestHeader -Request $Request -Name 'x-ms-client-principal'
    if (-not $header) { Stop-DgApi -Status 401 -Title 'Sign-in required' }
    try {
        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($header))
        $principal = ConvertFrom-Json -InputObject $json -AsHashtable -ErrorAction Stop
    } catch {
        Stop-DgApi -Status 401 -Title 'Sign-in required' -Detail 'the client principal header could not be read'
    }
    $upn = [string]$principal['userDetails']
    if (-not $upn) { Stop-DgApi -Status 401 -Title 'Sign-in required' }
    $roles = [string[]]@(@($principal['userRoles']) | Where-Object { $_ -in @('admin', 'reader') } | Sort-Object -Unique)
    [pscustomobject]@{
        PSTypeName = 'Dg.Caller'
        Upn        = $upn
        UserId     = [string]$principal['userId']
        Roles      = $roles
    }
}
