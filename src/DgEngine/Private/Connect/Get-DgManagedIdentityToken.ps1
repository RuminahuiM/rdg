function Get-DgManagedIdentityToken {
    <#
    .SYNOPSIS
        Gets an Entra access token for a user-assigned managed identity inside Azure Automation.
    .DESCRIPTION
        Uses the identity endpoint Azure Automation provides (IDENTITY_ENDPOINT and
        IDENTITY_HEADER), so no Az module is needed. Outside Automation, falls back to
        Get-AzAccessToken when Az.Accounts is loaded (local development).
        Returns @{ Token; ExpiresOn }.
    .EXAMPLE
        Get-DgManagedIdentityToken -Resource 'https://vault.azure.net' -ClientId $clientId
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Resource,

        [Parameter(Mandatory)]
        [string] $ClientId
    )

    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
        $resourceText = [System.Uri]::EscapeDataString($Resource)
        $clientText = [System.Uri]::EscapeDataString($ClientId)
        $uri = "$($env:IDENTITY_ENDPOINT)?resource=$resourceText&client_id=$clientText&api-version=2019-08-01"
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER; 'Metadata' = 'True' }
        $expires = [DateTimeOffset]::FromUnixTimeSeconds([long]$response.expires_on)
        return @{ Token = [string]$response.access_token; ExpiresOn = $expires }
    }
    if (Get-Command -Name Get-AzAccessToken -ErrorAction SilentlyContinue) {
        $token = Get-AzAccessToken -ResourceUrl $Resource -ErrorAction Stop
        $value = if ($token.Token -is [securestring]) { ConvertFrom-SecureString -SecureString $token.Token -AsPlainText } else { [string]$token.Token }
        return @{ Token = $value; ExpiresOn = [DateTimeOffset]$token.ExpiresOn }
    }
    throw "no managed identity endpoint (IDENTITY_ENDPOINT) and no Az.Accounts session; can't get a token for $Resource"
}
