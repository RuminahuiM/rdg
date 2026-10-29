function New-DgApiResponse {
    <#
    .SYNOPSIS
        Builds the HTTP response the function host sends: status, headers and a JSON body.
    .EXAMPLE
        New-DgApiResponse -Status 200 -Body $definition -ETag $etag
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [int] $Status,

        [AllowNull()]
        [object] $Body,

        [string] $ETag,

        [string] $Location,

        [string] $ContentType = 'application/json'
    )

    $headers = @{}
    if ($null -ne $Body) { $headers['Content-Type'] = $ContentType }
    if ($ETag) { $headers['ETag'] = $ETag }
    if ($Location) { $headers['Location'] = $Location }
    @{
        StatusCode = $Status
        Headers    = $headers
        Body       = if ($null -ne $Body) { ConvertTo-Json -InputObject $Body -Depth 30 -Compress } else { $null }
    }
}
