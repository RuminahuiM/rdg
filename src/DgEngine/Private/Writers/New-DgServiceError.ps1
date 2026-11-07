function New-DgServiceError {
    <#
    .SYNOPSIS
        Builds an exception that carries an HTTP status, for adapters and test doubles.
    .EXAMPLE
        throw (New-DgServiceError -StatusCode 429 -Message 'Too many requests' -RetryAfter 3)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param(
        [Parameter(Mandatory)]
        [int] $StatusCode,

        [Parameter(Mandatory)]
        [string] $Message,

        [int] $RetryAfter = 0
    )

    $exception = [System.Net.Http.HttpRequestException]::new("HTTP ${StatusCode}: $Message")
    $exception.Data['StatusCode'] = $StatusCode
    $exception.Data['RetryAfter'] = $RetryAfter
    $exception
}
