function Get-DgStoreError {
    <#
    .SYNOPSIS
        Turns an unexpected Cosmos DB response into an exception with the status code.
    .EXAMPLE
        throw (Get-DgStoreError -Response $response -Action 'reading lock-Entra')
    #>
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Response,

        [Parameter(Mandatory)]
        [string] $Action
    )

    $detail = [string]$Response.Content
    if ($detail.Length -gt 500) { $detail = $detail.Substring(0, 500) }
    New-DgServiceError -StatusCode ([int]$Response.StatusCode) -Message "Cosmos DB error while ${Action}: $detail"
}
