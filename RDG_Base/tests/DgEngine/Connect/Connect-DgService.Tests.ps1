#Requires -Version 7.4
# Connecting as the managed identity: Graph, Exchange, Cosmos DB token.

# The stand-ins mirror the real cmdlets' parameters, used or not.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stand-ins for foreign cmdlets.')]
param()

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
    $script:Log = [System.Collections.Generic.List[string]]::new()

    # Stand-ins for the Microsoft modules, as global functions the engine resolves.
    function global:Connect-MgGraph {
        [CmdletBinding()]
        param([switch] $Identity, [string] $ClientId, [switch] $NoWelcome)
        if ($ClientId -eq 'broken') { throw 'ManagedIdentityCredential authentication failed' }
        $script:Log.Add("graph $Identity $ClientId")
    }
    function global:Connect-ExchangeOnline {
        [CmdletBinding()]
        param([switch] $ManagedIdentity, [string] $Organization, [string] $ManagedIdentityAccountId, [string[]] $CommandName, [switch] $ShowBanner)
        $script:Log.Add("exchange $Organization $ManagedIdentityAccountId $($CommandName -join ',')")
    }
    function global:Invoke-RestMethod {
        param([string] $Method, [string] $Uri, [hashtable] $Headers)
        $script:Log.Add("token $Uri $($Headers['X-IDENTITY-HEADER'])")
        [pscustomobject]@{ access_token = 'abc'; expires_on = '1791800000' }
    }
    $script:Config = @{ ClientId = 'client-1'; TenantDomain = 'contoso.onmicrosoft.com'; CosmosEndpoint = 'https://rdg.documents.azure.com'; CosmosDatabase = 'rdg' }
}

AfterAll {
    Remove-Item -Path 'Function:\Connect-MgGraph', 'Function:\Connect-ExchangeOnline', 'Function:\Invoke-RestMethod' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Env:\IDENTITY_ENDPOINT', 'Env:\IDENTITY_HEADER' -ErrorAction SilentlyContinue
}

Describe 'Connect-DgService' {
    It 'connects Graph only for the Entra runbook and prepares the Cosmos store with the identity' {
        $script:Log.Clear()
        $connection = InModuleScope DgEngine -Parameters @{ C = $script:Config } { Connect-DgService -Provider Entra -Config $C }
        $script:Log -join ';' | Should -Be 'graph True client-1'
        $connection.Exchange | Should -BeNullOrEmpty
        $connection.Graph.Kind | Should -Be 'Graph'
        $connection.Store.ClientId | Should -Be 'client-1'
        $connection.Store.Endpoint | Should -Be 'https://rdg.documents.azure.com'
    }

    It 'connects Exchange with the managed identity and only the cmdlets the engine uses' {
        $script:Log.Clear()
        $connection = InModuleScope DgEngine -Parameters @{ C = $script:Config } { Connect-DgService -Provider Exchange -Config $C }
        $script:Log[1] | Should -BeLike 'exchange contoso.onmicrosoft.com client-1 Get-DistributionGroup,*Set-DistributionGroup'
        $connection.Exchange.Kind | Should -Be 'Exchange'
    }

    It 'names a missing configuration value' {
        { InModuleScope DgEngine { Connect-DgService -Provider Exchange -Config @{ ClientId = 'x'; CosmosEndpoint = 'https://a'; CosmosDatabase = 'b' } } } |
            Should -Throw -ExpectedMessage '*TenantDomain is missing*'
    }

    It 'says which connection failed' {
        $config = $script:Config.Clone()
        $config.ClientId = 'broken'
        { InModuleScope DgEngine -Parameters @{ C = $config } { Connect-DgService -Provider Entra -Config $C } } |
            Should -Throw -ExpectedMessage 'connecting to Microsoft Graph failed*'
    }
}

Describe 'Get-DgManagedIdentityToken' {
    It 'asks the Automation identity endpoint for the user-assigned identity' {
        $script:Log.Clear()
        $env:IDENTITY_ENDPOINT = 'http://127.0.0.1:1/msi/token'
        $env:IDENTITY_HEADER = 'secret-header'
        $token = InModuleScope DgEngine { Get-DgManagedIdentityToken -Resource 'https://vault.azure.net' -ClientId 'client-1' }
        $token.Token | Should -Be 'abc'
        $token.ExpiresOn.ToUnixTimeSeconds() | Should -Be 1791800000
        $script:Log[0] | Should -Be 'token http://127.0.0.1:1/msi/token?resource=https%3A%2F%2Fvault.azure.net&client_id=client-1&api-version=2019-08-01 secret-header'
    }

    It 'explains when there is no way to get a token' {
        Remove-Item -Path 'Env:\IDENTITY_ENDPOINT', 'Env:\IDENTITY_HEADER' -ErrorAction SilentlyContinue
        if (Get-Command -Name Get-AzAccessToken -ErrorAction SilentlyContinue) { return }
        { InModuleScope DgEngine { Get-DgManagedIdentityToken -Resource 'https://vault.azure.net' -ClientId 'client-1' } } |
            Should -Throw -ExpectedMessage '*no managed identity endpoint*'
    }

    It 'is used by the Cosmos store when the store has a client ID' {
        $script:Log.Clear()
        $env:IDENTITY_ENDPOINT = 'http://127.0.0.1:1/msi/token'
        $env:IDENTITY_HEADER = 'secret-header'
        $sent = InModuleScope DgEngine {
            $store = New-DgCosmosStore -Endpoint 'https://rdg.documents.azure.com' -Database 'rdg' -ManagedIdentityClientId 'client-1' `
                -Request { param($Method, $Uri, $Headers, $Body) @{ StatusCode = 404; Headers = @{}; Content = '' } }
            [void](Get-DgStoreItem -Store $store -Container state -Id 'x' -PartitionKey 'x')
            $store.Token.Token
        }
        $sent | Should -Be 'abc'
        $script:Log[0] | Should -BeLike '*resource=https%3A%2F%2Frdg.documents.azure.com&client_id=client-1*'
    }
}
