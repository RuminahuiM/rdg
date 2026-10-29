function New-DgCosmosStore {
    <#
    .SYNOPSIS
        Creates the store client for RDG's Cosmos DB account (containers config, state, runs).
    .DESCRIPTION
        Uses the Cosmos DB REST API with a Microsoft Entra token (no keys). Request and GetToken
        can be replaced, which is how the tests run without Azure:
          Request  { param($Method, $Uri, $Headers, $Body) } -> @{ StatusCode; Headers; Content }
          GetToken { param($Resource) } -> @{ Token = <string>; ExpiresOn = <DateTimeOffset> }
        With -ManagedIdentityClientId the token comes from the Automation identity endpoint
        (Get-DgManagedIdentityToken); otherwise from Get-AzAccessToken (local development).
    .EXAMPLE
        $store = New-DgCosmosStore -Endpoint 'https://rdg-contoso.documents.azure.com' -Database 'rdg'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://')]
        [string] $Endpoint,

        [Parameter(Mandatory)]
        [string] $Database,

        [scriptblock] $Request = {
            param([string] $Method, [string] $Uri, [hashtable] $Headers, [string] $Body)
            $call = @{ Method = $Method; Uri = $Uri; Headers = $Headers; SkipHttpErrorCheck = $true; SkipHeaderValidation = $true }
            if ($Body) { $call.Body = $Body }
            $response = Invoke-WebRequest @call
            $headers = @{}
            foreach ($key in $response.Headers.Keys) { $headers[$key] = [string](@($response.Headers[$key])[0]) }
            @{ StatusCode = [int]$response.StatusCode; Headers = $headers; Content = [string]$response.Content }
        },

        [scriptblock] $GetToken = {
            param([string] $Resource)
            $token = Get-AzAccessToken -ResourceUrl $Resource -ErrorAction Stop
            $value = if ($token.Token -is [securestring]) { ConvertFrom-SecureString -SecureString $token.Token -AsPlainText } else { [string]$token.Token }
            @{ Token = $value; ExpiresOn = [DateTimeOffset]$token.ExpiresOn }
        },

        [scriptblock] $Sleep = { param([double] $Seconds) Start-Sleep -Milliseconds ([int]($Seconds * 1000)) },

        # Client ID of the user-assigned managed identity; takes precedence over GetToken.
        [string] $ManagedIdentityClientId
    )

    @{
        Kind     = 'Cosmos'
        # Scheme and host only: the account endpoint Azure reports ends in ':443/', and Entra
        # rejects a token audience with a port (managed identity endpoint answers 400).
        Endpoint = ([System.Uri]$Endpoint).GetLeftPart([System.UriPartial]::Authority)
        Database = $Database
        Request  = $Request
        GetToken = $GetToken
        Sleep    = $Sleep
        Token    = $null
        ClientId = $ManagedIdentityClientId
    }
}
