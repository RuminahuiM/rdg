function Get-DgApiContext {
    <#
    .SYNOPSIS
        The per-worker API context: Cosmos store, Graph directory, access mode, version, job
        starter and caches. Built once from the Function App's app settings.
    .DESCRIPTION
        App settings: DG_ApiClientId (the "api" managed identity), DG_CosmosEndpoint,
        DG_CosmosDatabase, DG_AccessMode, DG_AutomationAccountId (resource ID of the Automation
        account). Tests and the local host set the context with Set-DgApiContext instead.
        Graph is connected on first use only, so health checks never need it.
    .EXAMPLE
        $context = Get-DgApiContext
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:DgApiContext) { return $script:DgApiContext }
    foreach ($name in @('DG_ApiClientId', 'DG_CosmosEndpoint', 'DG_CosmosDatabase')) {
        if (-not [System.Environment]::GetEnvironmentVariable($name)) { throw "the app setting $name is missing" }
    }
    $clientId = $env:DG_ApiClientId
    $store = Invoke-DgEngine -Name New-DgCosmosStore -Parameters @{
        Endpoint = $env:DG_CosmosEndpoint; Database = $env:DG_CosmosDatabase; ManagedIdentityClientId = $clientId
    }
    $script:DgApiContext = @{
        Store               = $store
        Graph               = $null
        ConnectGraph        = {
            param([string] $ClientId)
            Connect-MgGraph -Identity -ClientId $ClientId -NoWelcome -ErrorAction Stop | Out-Null
        }
        ClientId            = $clientId
        AccessMode          = if ($env:DG_AccessMode -eq 'read-write') { 'read-write' } else { 'read-only' }
        AutomationAccountId = [string]$env:DG_AutomationAccountId
        StartJob            = $null
        Version             = Get-DgEngineVersion
        Now                 = { [DateTimeOffset]::UtcNow }
        UserCache           = @{}
    }
    $script:DgApiContext
}
