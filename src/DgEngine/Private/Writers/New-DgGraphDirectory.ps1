function New-DgGraphDirectory {
    <#
    .SYNOPSIS
        Creates the Microsoft Graph directory used for users, memberOf lookups and Entra groups.
    .DESCRIPTION
        Request is called as & $Request -Method <m> -Uri <absolute uri> -Body <object or $null>
        and returns the parsed JSON as a hashtable. The default uses Invoke-MgGraphRequest
        (Microsoft.Graph.Authentication, signed in with the managed identity). Tests pass a fake.
        MarkerExtension is the directory extension property used as marker on Entra groups, or
        empty when the marker is off.
    .EXAMPLE
        $graph = New-DgGraphDirectory
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [scriptblock] $Request = {
            param([string] $Method, [string] $Uri, [object] $Body)
            $call = @{ Method = $Method; Uri = $Uri; OutputType = 'Hashtable' }
            if ($null -ne $Body) {
                $call.Body = $Body | ConvertTo-Json -Depth 10 -Compress
                $call.ContentType = 'application/json'
            }
            Invoke-MgGraphRequest @call
        },

        [scriptblock] $Sleep = { param([double] $Seconds) Start-Sleep -Milliseconds ([int]($Seconds * 1000)) },

        [string] $MarkerExtension
    )

    @{
        Kind            = 'Graph'
        BaseUri         = 'https://graph.microsoft.com/v1.0'
        Request         = $Request
        Sleep           = $Sleep
        MarkerExtension = $MarkerExtension
    }
}
