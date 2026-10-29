#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }, @{ ModuleName = 'Az.Resources'; ModuleVersion = '7.0.0' }, @{ ModuleName = 'Az.Storage'; ModuleVersion = '7.0.0' }, @{ ModuleName = 'Az.KeyVault'; ModuleVersion = '6.0.0' }
<#
.SYNOPSIS
    RDG bootstrap stage 1: the Azure side that has to exist before the first pipeline run.
.DESCRIPTION
    Run once per installation by a person with Owner on the subscription (signed in with
    Connect-AzAccount). Idempotent: a rerun only creates what is missing. It
      1. registers the resource providers RDG uses,
      2. creates the resource groups rg-<prefix>-<env> and rg-<prefix>-<env>-bootstrap,
      3. creates the state storage account (shared keys off, versioning, 30-day soft delete) and
         its container tfstate,
      4. creates the state Key Vault (RBAC, purge protection) and the RSA key that encrypts the
         OpenTofu state; you get Key Vault Crypto Officer on the vault for this step only,
      5. creates the pipeline's app registration with a federated credential for the Azure
         DevOps service connection, or uses an existing service principal (-PipelinePrincipalId),
      6. gives the pipeline: Contributor and a conditioned Role Based Access Control
         Administrator on rg-<prefix>-<env>, Storage Blob Data Contributor on the state container
         and Key Vault Crypto User on the state key.
    It prints the values for the service connection, the backend and the settings file.
    Reference: Infrastructure design ("Bootstrap"), Identity and Access design ("Pipeline identity").
.PARAMETER SettingsFile
    The installation's settings file; name_prefix, environment and location are read from it.
    Explicit parameters win.
.PARAMETER FederationIssuer
    Issuer of the Azure DevOps service connection (workload identity federation), for example
    https://vstoken.dev.azure.com/<organization ID>.
.PARAMETER FederationSubject
    Subject of the service connection, for example sc://contoso/rdg/rdg-prod.
.PARAMETER LocalOnly
    No Azure DevOps pipeline yet: you run deploy/Deploy-Rdg.ps1 yourself. Instead of a pipeline
    identity, you (the person running this) get write access to the state container and use of
    the state key; pipeline_principal_id is your own object ID.
.PARAMETER PipelinePrincipalId
    Object ID of an existing service principal (for example one Azure DevOps created with the
    service connection). The script then creates no app registration and only assigns roles.
.EXAMPLE
    ./bootstrap/Initialize-RdgAzure.ps1 -SubscriptionId $sub -SettingsFile ./rdg-prod.tfvars `
        -FederationIssuer 'https://vstoken.dev.azure.com/00000000-0000-0000-0000-000000000000' `
        -FederationSubject 'sc://contoso/rdg/rdg-prod'
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'NewPipelineApp')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string] $SubscriptionId,

    [string] $SettingsFile,

    [ValidatePattern('^[a-z][a-z0-9]{1,5}$')]
    [string] $NamePrefix,

    [ValidatePattern('^[a-z0-9]{2,7}$')]
    [string] $Environment,

    [string] $Location,

    [Parameter(Mandatory, ParameterSetName = 'NewPipelineApp')]
    [ValidatePattern('^https://')]
    [string] $FederationIssuer,

    [Parameter(Mandatory, ParameterSetName = 'NewPipelineApp')]
    [string] $FederationSubject,

    [Parameter(Mandatory, ParameterSetName = 'ExistingPipeline')]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string] $PipelinePrincipalId,

    # No pipeline yet: you deploy by hand (deploy/Deploy-Rdg.ps1). You get write access to the
    # state and use of the state key instead of a pipeline identity; no app registration.
    [Parameter(Mandatory, ParameterSetName = 'LocalOnly')]
    [switch] $LocalOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RdgBootstrap.psm1') -Force

function Write-Step {
    param([string] $Message)
    Write-Information -MessageData "-- $Message" -InformationAction Continue
}

function Invoke-WithRetry {
    # Role assignments and new service principals take a while to reach every Azure region.
    param([scriptblock] $Action, [string] $What, [int] $Attempts = 12, [int] $DelaySeconds = 15)
    for ($i = 1; ; $i++) {
        try { return & $Action } catch {
            if ($i -ge $Attempts) { throw "$What failed after $Attempts attempts: $($_.Exception.Message)" }
            Write-Verbose -Message "$What not ready yet ($($_.Exception.Message)); retrying in $DelaySeconds s"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Set-RoleAssignment {
    # Assigns a role if the principal doesn't hold it at that scope yet.
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $ObjectId, [string] $RoleDefinitionId, [string] $Scope, [string] $Condition, [string] $ObjectType = 'ServicePrincipal')
    $existing = @(Get-AzRoleAssignment -ObjectId $ObjectId -Scope $Scope -ErrorAction SilentlyContinue |
            Where-Object { $_.Scope -eq $Scope -and $_.RoleDefinitionId -eq $RoleDefinitionId })
    if ($existing.Count -gt 0) {
        if ($Condition -and $existing[0].Condition -ne $Condition) {
            Write-Warning -Message "The role $RoleDefinitionId at $Scope has a different condition; remove it and rerun to apply the current one."
        }
        return $false
    }
    if (-not $PSCmdlet.ShouldProcess($Scope, "Assign role $RoleDefinitionId to $ObjectId")) { return $false }
    $assignment = @{ ObjectId = $ObjectId; RoleDefinitionId = $RoleDefinitionId; Scope = $Scope; ObjectType = $ObjectType }
    if ($Condition) { $assignment.Condition = $Condition; $assignment.ConditionVersion = '2.0' }
    Invoke-WithRetry -What "Role assignment at $Scope" -Action { [void](New-AzRoleAssignment @assignment) }
    $true
}

# --- Settings
$settings = if ($SettingsFile) { Read-RdgSettingsFile -Path $SettingsFile } else { @{} }
if (-not $NamePrefix) { $NamePrefix = if ($settings['name_prefix']) { [string]$settings.name_prefix } else { 'rdg' } }
if (-not $Environment) { $Environment = if ($settings['environment']) { [string]$settings.environment } else { 'prod' } }
if (-not $Location) { $Location = if ($settings['location']) { [string]$settings.location } else { 'westeurope' } }
$names = Get-RdgResourceName -NamePrefix $NamePrefix -Environment $Environment -SubscriptionId $SubscriptionId
$tags = @{ app = 'rdg'; environment = $Environment; 'managed-by' = 'bootstrap' }
$roles = @{
    Contributor         = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
    RbacAdministrator   = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
    BlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    CryptoUser          = '12338af0-0e69-4776-bea7-57ae8d297424'
    CryptoOfficer       = '14b46e9e-c2b7-41b4-b07b-48a6ebf60603'
}

$context = Get-AzContext
if (-not $context) { throw 'Not signed in. Run Connect-AzAccount first.' }
if ($context.Subscription.Id -ne $SubscriptionId) { $context = Set-AzContext -Subscription $SubscriptionId }
$tenantId = $context.Tenant.Id

# --- 1. Resource providers
Write-Step 'Resource providers'
$providers = @('Microsoft.Automation', 'Microsoft.DocumentDB', 'Microsoft.Web', 'Microsoft.Storage', 'Microsoft.KeyVault',
    'Microsoft.ManagedIdentity', 'Microsoft.Insights', 'Microsoft.Consumption')
foreach ($namespace in $providers) {
    $state = (Get-AzResourceProvider -ProviderNamespace $namespace | Select-Object -First 1).RegistrationState
    if ($state -ne 'Registered' -and $PSCmdlet.ShouldProcess($namespace, 'Register resource provider')) {
        [void](Register-AzResourceProvider -ProviderNamespace $namespace)
    }
}

# --- 2. Resource groups
Write-Step 'Resource groups'
$groups = @{}
foreach ($name in @($names.ResourceGroup, $names.BootstrapGroup)) {
    $group = Get-AzResourceGroup -Name $name -ErrorAction SilentlyContinue
    if (-not $group -and $PSCmdlet.ShouldProcess($name, 'Create resource group')) {
        $group = New-AzResourceGroup -Name $name -Location $Location -Tag $tags
    }
    $groups[$name] = $group
}

# --- 3. State storage
Write-Step "State storage $($names.StateStorageAccount)"
$storage = Get-AzStorageAccount -ResourceGroupName $names.BootstrapGroup -Name $names.StateStorageAccount -ErrorAction SilentlyContinue
if (-not $storage -and $PSCmdlet.ShouldProcess($names.StateStorageAccount, 'Create storage account')) {
    $storage = New-AzStorageAccount -ResourceGroupName $names.BootstrapGroup -Name $names.StateStorageAccount -Location $Location `
        -SkuName Standard_LRS -Kind StorageV2 -MinimumTlsVersion TLS1_2 -EnableHttpsTrafficOnly $true `
        -AllowBlobPublicAccess $false -AllowSharedKeyAccess $false -Tag $tags
}
if ($storage -and $PSCmdlet.ShouldProcess($names.StateStorageAccount, 'Turn on versioning and 30-day soft delete')) {
    [void](Update-AzStorageBlobServiceProperty -ResourceGroupName $names.BootstrapGroup -StorageAccountName $names.StateStorageAccount -IsVersioningEnabled $true)
    [void](Enable-AzStorageBlobDeleteRetentionPolicy -ResourceGroupName $names.BootstrapGroup -StorageAccountName $names.StateStorageAccount -RetentionDays 30)
    [void](Enable-AzStorageContainerDeleteRetentionPolicy -ResourceGroupName $names.BootstrapGroup -StorageAccountName $names.StateStorageAccount -RetentionDays 30)
}
$container = Get-AzRmStorageContainer -ResourceGroupName $names.BootstrapGroup -StorageAccountName $names.StateStorageAccount -Name $names.StateContainer -ErrorAction SilentlyContinue
if (-not $container -and $storage -and $PSCmdlet.ShouldProcess($names.StateContainer, 'Create container')) {
    # Created through Azure Resource Manager: shared keys are off on this account.
    $container = New-AzRmStorageContainer -ResourceGroupName $names.BootstrapGroup -StorageAccountName $names.StateStorageAccount -Name $names.StateContainer
}

# --- 4. State Key Vault and key
Write-Step "State Key Vault $($names.StateKeyVault)"
$vault = Get-AzKeyVault -ResourceGroupName $names.BootstrapGroup -VaultName $names.StateKeyVault -ErrorAction SilentlyContinue
if (-not $vault) {
    # After Uninstall-Rdg.ps1 the vault is soft-deleted for 90 days (purge protection) and its name
    # is taken: recover it, key included, instead of creating a new one.
    $deleted = Get-AzKeyVault -InRemovedState -ErrorAction SilentlyContinue | Where-Object { $_.VaultName -eq $names.StateKeyVault } | Select-Object -First 1
    if ($deleted -and $PSCmdlet.ShouldProcess($names.StateKeyVault, 'Recover the soft-deleted Key Vault')) {
        [void](Undo-AzKeyVaultRemoval -VaultName $names.StateKeyVault -ResourceGroupName $names.BootstrapGroup -Location $deleted.Location)
        $vault = Get-AzKeyVault -ResourceGroupName $names.BootstrapGroup -VaultName $names.StateKeyVault
    }
}
if (-not $vault -and $PSCmdlet.ShouldProcess($names.StateKeyVault, 'Create Key Vault (RBAC, purge protection)')) {
    # Az.KeyVault 6 creates vaults in RBAC mode by default.
    $vault = New-AzKeyVault -ResourceGroupName $names.BootstrapGroup -VaultName $names.StateKeyVault -Location $Location `
        -Sku Standard -EnablePurgeProtection -SoftDeleteRetentionInDays 90 -Tag $tags
}
if ($vault) {
    $key = Get-AzKeyVaultKey -VaultName $names.StateKeyVault -Name $names.StateKeyName -ErrorAction SilentlyContinue
    if (-not $key -and $PSCmdlet.ShouldProcess($names.StateKeyName, 'Create RSA key for state encryption')) {
        $me = (Get-AzADUser -SignedIn).Id
        $granted = Set-RoleAssignment -ObjectId $me -ObjectType User -RoleDefinitionId $roles.CryptoOfficer -Scope $vault.ResourceId
        try {
            [void](Invoke-WithRetry -What 'Creating the state key' -Action {
                    Add-AzKeyVaultKey -VaultName $names.StateKeyVault -Name $names.StateKeyName -Destination Software -KeyType RSA -Size 4096
                })
        } finally {
            if ($granted) {
                Get-AzRoleAssignment -ObjectId $me -Scope $vault.ResourceId |
                    Where-Object { $_.Scope -eq $vault.ResourceId -and $_.RoleDefinitionId -eq $roles.CryptoOfficer } |
                    Remove-AzRoleAssignment | Out-Null
            }
        }
    }
}

# --- 5. Pipeline identity
Write-Step 'Pipeline identity'
$pipelineAppId = $null
if ($PSCmdlet.ParameterSetName -eq 'NewPipelineApp') {
    $app = @(Get-AzADApplication -DisplayName $names.PipelineApp -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (-not $app -and $PSCmdlet.ShouldProcess($names.PipelineApp, 'Create app registration')) {
        $app = New-AzADApplication -DisplayName $names.PipelineApp -SignInAudience AzureADMyOrg
    }
    if ($app) {
        $pipelineAppId = $app.AppId
        $principal = Get-AzADServicePrincipal -ApplicationId $app.AppId -ErrorAction SilentlyContinue
        if (-not $principal -and $PSCmdlet.ShouldProcess($names.PipelineApp, 'Create service principal')) {
            $principal = New-AzADServicePrincipal -ApplicationId $app.AppId
        }
        $credentials = @(Get-AzADAppFederatedCredential -ApplicationObjectId $app.Id -ErrorAction SilentlyContinue)
        $match = @($credentials | Where-Object { $_.Issuer -eq $FederationIssuer -and $_.Subject -eq $FederationSubject })
        if ($match.Count -eq 0 -and $PSCmdlet.ShouldProcess($names.PipelineApp, "Add federated credential for $FederationSubject")) {
            $credentialName = 'azure-devops-' + ([regex]::Replace($FederationSubject.ToLowerInvariant(), '[^a-z0-9]+', '-')).Trim('-')
            if ($credentialName.Length -gt 120) { $credentialName = $credentialName.Substring(0, 120) }
            [void](New-AzADAppFederatedCredential -ApplicationObjectId $app.Id -Name $credentialName -Issuer $FederationIssuer `
                    -Subject $FederationSubject -Audience 'api://AzureADTokenExchange')
        }
        if ($principal) { $PipelinePrincipalId = $principal.Id }
    }
} elseif ($LocalOnly) {
    # The person running this deploys by hand; they need no Contributor (they are Owner).
    $PipelinePrincipalId = (Get-AzADUser -SignedIn).Id
} else {
    $principal = Get-AzADServicePrincipal -ObjectId $PipelinePrincipalId
    $pipelineAppId = $principal.AppId
}

# --- 6. Pipeline roles
Write-Step 'Pipeline roles'
$principalType = if ($LocalOnly) { 'User' } else { 'ServicePrincipal' }
if ($PipelinePrincipalId) {
    # Under -WhatIf the group doesn't exist yet; StrictMode forbids reading a property of $null.
    $rdgGroup = Get-AzResourceGroup -Name $names.ResourceGroup -ErrorAction SilentlyContinue
    $groupId = if ($rdgGroup) { $rdgGroup.ResourceId } else { $null }
    if ($groupId -and -not $LocalOnly) {
        [void](Set-RoleAssignment -ObjectId $PipelinePrincipalId -RoleDefinitionId $roles.Contributor -Scope $groupId)
        $condition = Get-RdgRoleAssignmentCondition -RoleDefinitionId ([string[]]@((Get-RdgPipelineRole).Values))
        [void](Set-RoleAssignment -ObjectId $PipelinePrincipalId -RoleDefinitionId $roles.RbacAdministrator -Scope $groupId -Condition $condition)
    }
    if ($storage) {
        $containerScope = "$($storage.Id)/blobServices/default/containers/$($names.StateContainer)"
        [void](Set-RoleAssignment -ObjectId $PipelinePrincipalId -ObjectType $principalType -RoleDefinitionId $roles.BlobDataContributor -Scope $containerScope)
    }
    if ($vault) {
        $keyScope = "$($vault.ResourceId)/keys/$($names.StateKeyName)"
        [void](Set-RoleAssignment -ObjectId $PipelinePrincipalId -ObjectType $principalType -RoleDefinitionId $roles.CryptoUser -Scope $keyScope)
    }
}

# --- Result
$result = [pscustomobject]@{
    TenantId             = $tenantId
    SubscriptionId       = $SubscriptionId
    PipelineAppId        = $pipelineAppId
    PipelinePrincipalId  = $PipelinePrincipalId
    BackendResourceGroup = $names.BootstrapGroup
    BackendStorage       = $names.StateStorageAccount
    BackendContainer     = $names.StateContainer
    BackendKey           = $names.StateKey
    StateKeyVaultName    = $names.StateKeyVault
}
Write-Information -InformationAction Continue -MessageData @"

Stage 1 done.

Azure DevOps service connection (workload identity federation, manual):
  Subscription ID   $SubscriptionId
  Tenant ID         $tenantId
  Client ID         $pipelineAppId

OpenTofu backend (tofu init -backend-config=...):
  resource_group_name  = $($names.BootstrapGroup)
  storage_account_name = $($names.StateStorageAccount)
  container_name       = $($names.StateContainer)
  key                  = $($names.StateKey)

Settings file:
  state_key_vault_name  = "$($names.StateKeyVault)"
  pipeline_principal_id = "$PipelinePrincipalId"

Next: run the pipeline once (sign-in stays off), then bootstrap/Initialize-RdgTenant.ps1.
"@
$result
