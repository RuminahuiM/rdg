#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }, @{ ModuleName = 'Az.Resources'; ModuleVersion = '7.0.0' }, @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.20.0' }
<#
.SYNOPSIS
    Removes everything a test phase created, and leaves the installation itself in place.
.DESCRIPTION
    Undoes the read-only test plan in one run:
      1. Definitions: every definition whose name starts with -Prefix, or whose target group is
         one of the test groups, with everything stored under it (status, runs, audit entries).
         Cosmos DB accepts only Entra tokens with a data role, so you get "Cosmos DB Built-in
         Data Contributor" on the RDG database for this step only; it is removed again at the end.
      2. Settings (-ResetSettings): the settings document and its audit entries; the API
         recreates the defaults on next use.
      3. The test groups (bootstrap/New-RdgTestGroups.ps1 -Remove), unless -KeepGroups.
      4. Your temporary log reader role (Storage Blob Data Reader on the functions storage).
    Run it with -WhatIf first: it then changes nothing and lists what it would remove. Without
    an existing data role it can't look into Cosmos DB under -WhatIf and says so.
    Signed in with Connect-AzAccount as Owner (or User Access Administrator) of the RDG group.
.EXAMPLE
    ./bootstrap/Remove-RdgTestData.ps1 -SubscriptionId $sub -SettingsFile ./settings/eval.tfvars -WhatIf
.EXAMPLE
    ./bootstrap/Remove-RdgTestData.ps1 -SubscriptionId $sub -SettingsFile ./settings/eval.tfvars -ResetSettings
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $SettingsFile,

    [ValidatePattern('^[A-Za-z0-9-]{1,20}$')]
    [string] $Prefix = 'RDG-Test-',

    [switch] $ResetSettings,

    [switch] $KeepGroups
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RdgBootstrap.psm1') -Force

$settings = Read-RdgSettingsFile -Path $SettingsFile
$namePrefix = if ($settings['name_prefix']) { [string]$settings['name_prefix'] } else { 'rdg' }
$environment = if ($settings['environment']) { [string]$settings['environment'] } else { 'prod' }
$names = Get-RdgResourceName -NamePrefix $namePrefix -Environment $environment -SubscriptionId $SubscriptionId

$context = Get-AzContext
if (-not $context) { throw 'Not signed in to Azure. Run Connect-AzAccount first.' }
if ($context.Subscription.Id -ne $SubscriptionId) { [void](Set-AzContext -Subscription $SubscriptionId) ; $context = Get-AzContext }
$tenantId = [string]$context.Tenant.Id
$me = Get-AzADUser -SignedIn
$database = 'rdg'
$account = Get-AzResource -ResourceGroupName $names.ResourceGroup -ResourceType 'Microsoft.DocumentDB/databaseAccounts' -Name $names.CosmosAccount -ErrorAction SilentlyContinue
if (-not $account) { throw "Cosmos DB account $($names.CosmosAccount) not found in $($names.ResourceGroup)." }
$endpoint = "https://$($names.CosmosAccount).documents.azure.com"

function Write-Step { param([string] $Message) Write-Information -InformationAction Continue -MessageData "-- $Message" }

function Invoke-Cosmos {
    # One Cosmos DB REST call with your Entra token. Returns StatusCode and parsed Content.
    param([string] $Method, [string] $Path, [string] $PartitionKey, [string] $Body, [hashtable] $Headers = @{})
    $token = (Get-AzAccessToken -ResourceUrl $endpoint).Token
    if ($token -is [securestring]) { $token = ConvertFrom-SecureString -SecureString $token -AsPlainText }
    $send = @{
        Authorization  = [uri]::EscapeDataString("type=aad&ver=1.0&sig=$token")
        'x-ms-date'    = [DateTime]::UtcNow.ToString('r', [Globalization.CultureInfo]::InvariantCulture)
        'x-ms-version' = '2018-12-31'
    }
    if ($PartitionKey) { $send['x-ms-documentdb-partitionkey'] = ConvertTo-Json -InputObject @($PartitionKey) -Compress }
    foreach ($key in $Headers.Keys) { $send[$key] = $Headers[$key] }
    $request = @{ Method = $Method; Uri = "$endpoint/$Path"; Headers = $send; SkipHttpErrorCheck = $true }
    if ($Body) { $request.Body = $Body; $request.ContentType = if ($Headers['Content-Type']) { $Headers['Content-Type'] } else { 'application/json' } }
    $response = Invoke-WebRequest @request
    $text = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
    $next = $response.Headers['x-ms-continuation']
    [pscustomobject]@{
        StatusCode   = [int]$response.StatusCode
        Content      = if ($text) { $text | ConvertFrom-Json -AsHashtable } else { $null }
        Continuation = if ($next) { [string]@($next)[0] } else { $null }
    }
}

function Find-CosmosItem {
    # Every document of a container matching a query, across partitions and pages.
    param([string] $Container, [string] $Query, [object[]] $Parameters = @())
    $body = @{ query = $Query; parameters = @($Parameters) } | ConvertTo-Json -Depth 5 -Compress
    $continuation = $null
    do {
        $headers = @{ 'Content-Type' = 'application/query+json'; 'x-ms-documentdb-isquery' = 'True'; 'x-ms-documentdb-query-enablecrosspartition' = 'True' }
        if ($continuation) { $headers['x-ms-continuation'] = $continuation }
        $response = Invoke-Cosmos -Method POST -Path "dbs/$database/colls/$Container/docs" -Body $body -Headers $headers
        if ($response.StatusCode -ne 200) { throw "Cosmos DB query on $Container answered $($response.StatusCode): $($response.Content | ConvertTo-Json -Compress)" }
        foreach ($item in @($response.Content['Documents'])) { $item }
        $continuation = $response.Continuation
    } while ($continuation)
}

# --- Test groups (read)
Connect-MgGraph -TenantId $tenantId -NoWelcome -Scopes @('Group.Read.All')
$filter = [uri]::EscapeDataString("startswith(displayName,'$Prefix')")
$testGroups = @(Invoke-RdgGraphRequest -Method GET -Uri "/groups?`$filter=$filter&`$select=id,displayName" -All)
Write-Step "Test groups: $($testGroups.Count) ($(@($testGroups | ForEach-Object { $_.displayName }) -join ', '))"
$testGroupIds = @($testGroups | ForEach-Object { [string]$_.id })

# --- 1 + 2. Cosmos DB documents
$roleDefinition = "$($account.ResourceId)/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
$roleScope = "$($account.ResourceId)/dbs/$database"
$assignments = (Invoke-AzRestMethod -Method GET -Path "$($account.ResourceId)/sqlRoleAssignments?api-version=2024-05-15").Content | ConvertFrom-Json
$existing = @($assignments.value | Where-Object { $_.properties.principalId -eq $me.Id -and $_.properties.roleDefinitionId -eq $roleDefinition })
$temporary = $null
try {
    if (-not $existing -and $PSCmdlet.ShouldProcess($names.CosmosAccount, 'Give yourself Cosmos DB Built-in Data Contributor on the RDG database (removed at the end)')) {
        $temporary = [guid]::NewGuid().ToString()
        $body = @{ properties = @{ roleDefinitionId = $roleDefinition; scope = $roleScope; principalId = $me.Id } } | ConvertTo-Json -Depth 5
        $put = Invoke-AzRestMethod -Method PUT -Path "$($account.ResourceId)/sqlRoleAssignments/$($temporary)?api-version=2024-05-15" -Payload $body
        if ($put.StatusCode -ge 300) { $temporary = $null; throw "Granting the Cosmos DB data role failed: $($put.Content)" }
    }
    $canRead = [bool]$existing -or [bool]$temporary
    if (-not $canRead) {
        Write-Step 'Cosmos DB: under -WhatIf without a data role nothing can be listed. A real run deletes every definition'
        Write-Information -InformationAction Continue -MessageData "   named '$Prefix*' or targeting a test group, with its status, runs and audit entries$(if ($ResetSettings) { ', and resets the settings' })."
    } else {
        # A new data-plane role assignment takes a moment to apply.
        $definitions = $null
        for ($attempt = 1; $null -eq $definitions; $attempt++) {
            try { $definitions = @(Find-CosmosItem -Container config -Query "SELECT c.id, c.name, c.target FROM c WHERE c.type = 'definition'") } catch {
                if ($attempt -ge 20 -or "$_" -notmatch '\b403\b') { throw }
                Start-Sleep -Seconds 15
            }
        }
        $selected = @($definitions | Where-Object {
                ([string]$_['name']).StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) -or
                ($_['target'] -and $testGroupIds -contains [string]$_['target']['groupId'])
            })
        Write-Step "Definitions to remove: $($selected.Count) of $($definitions.Count)"
        $partitions = @($selected | ForEach-Object { [string]$_['id'] })
        if ($ResetSettings) { $partitions += 'settings' }
        foreach ($partition in $partitions) {
            $label = if ($partition -eq 'settings') { 'settings' } else { "$partition ($(($selected | Where-Object { $_['id'] -eq $partition })['name']))" }
            foreach ($container in @('config', 'state', 'runs')) {
                $items = @(Find-CosmosItem -Container $container -Query 'SELECT c.id FROM c WHERE c.pk = @pk' -Parameters @(@{ name = '@pk'; value = $partition }))
                if (-not $items) { continue }
                if ($PSCmdlet.ShouldProcess("$container/$label", "Delete $($items.Count) document(s)")) {
                    foreach ($item in $items) {
                        $delete = Invoke-Cosmos -Method DELETE -Path "dbs/$database/colls/$container/docs/$([uri]::EscapeDataString([string]$item['id']))" -PartitionKey $partition
                        if ($delete.StatusCode -notin @(204, 404)) { throw "Deleting $container/$($item['id']) answered $($delete.StatusCode)" }
                    }
                }
            }
        }
    }
} finally {
    if ($temporary) {
        Write-Step 'Removing the temporary Cosmos DB data role'
        [void](Invoke-AzRestMethod -Method DELETE -Path "$($account.ResourceId)/sqlRoleAssignments/$($temporary)?api-version=2024-05-15")
    }
}

# --- 3. Test groups
if (-not $KeepGroups -and $testGroups) {
    Write-Step 'Test groups'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'New-RdgTestGroups.ps1') -TenantId $tenantId -Prefix $Prefix -Remove -WhatIf:$WhatIfPreference -Confirm:$false
}

# --- 4. Temporary log reader role
$storage = Get-AzResource -ResourceGroupName $names.ResourceGroup -ResourceType 'Microsoft.Storage/storageAccounts' -Name $names.FunctionsStorage -ErrorAction SilentlyContinue
if ($storage) {
    $reader = @(Get-AzRoleAssignment -ObjectId $me.Id -Scope $storage.ResourceId -RoleDefinitionName 'Storage Blob Data Reader' -ErrorAction SilentlyContinue |
            Where-Object { $_.Scope -eq $storage.ResourceId })
    if ($reader -and $PSCmdlet.ShouldProcess($names.FunctionsStorage, 'Remove your Storage Blob Data Reader role')) {
        Remove-AzRoleAssignment -ObjectId $me.Id -Scope $storage.ResourceId -RoleDefinitionName 'Storage Blob Data Reader' | Out-Null
    }
}
Write-Step 'Done'
