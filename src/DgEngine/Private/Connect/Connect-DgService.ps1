function Connect-DgService {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph, Exchange Online (Exchange runbook only) and Cosmos DB as the
        engine's user-assigned managed identity, and returns the directories and the store.
    .DESCRIPTION
        Config: ClientId, TenantDomain, CosmosEndpoint, CosmosDatabase, MarkerExtension
        (optional). Graph goes through Microsoft.Graph.Authentication (Invoke-MgGraphRequest),
        Exchange through ExchangeOnlineManagement with only the cmdlets the engine uses.
        Any failure throws, so the job fails and the alert fires.
    .EXAMPLE
        $connection = Connect-DgService -Provider Exchange -Config $config
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Entra', 'Exchange')]
        [string] $Provider,

        [Parameter(Mandatory)]
        [hashtable] $Config
    )

    foreach ($name in @('ClientId', 'CosmosEndpoint', 'CosmosDatabase')) {
        if (-not $Config[$name]) { throw "the configuration value $name is missing" }
    }
    if ($Provider -eq 'Exchange' -and -not $Config['TenantDomain']) { throw 'the configuration value TenantDomain is missing' }
    $clientId = [string]$Config.ClientId

    try {
        Connect-MgGraph -Identity -ClientId $clientId -NoWelcome -ErrorAction Stop | Out-Null
    } catch {
        throw "connecting to Microsoft Graph failed: $($_.Exception.Message)"
    }
    $graph = New-DgGraphDirectory -MarkerExtension ([string]$Config['MarkerExtension'])

    $exchange = $null
    if ($Provider -eq 'Exchange') {
        $commands = @(
            'Get-DistributionGroup', 'Get-DistributionGroupMember', 'Add-DistributionGroupMember',
            'Remove-DistributionGroupMember', 'New-DistributionGroup', 'Set-DistributionGroup'
        )
        try {
            Connect-ExchangeOnline -ManagedIdentity -Organization ([string]$Config.TenantDomain) -ManagedIdentityAccountId $clientId `
                -CommandName $commands -ShowBanner:$false -ErrorAction Stop | Out-Null
        } catch {
            throw "connecting to Exchange Online failed: $($_.Exception.Message)"
        }
        $exchange = New-DgExchangeDirectory
    }

    $store = New-DgCosmosStore -Endpoint ([string]$Config.CosmosEndpoint) -Database ([string]$Config.CosmosDatabase) -ManagedIdentityClientId $clientId

    [pscustomobject]@{
        Graph    = $graph
        Exchange = $exchange
        Store    = $store
    }
}
