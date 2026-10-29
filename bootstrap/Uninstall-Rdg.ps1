#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }, @{ ModuleName = 'Az.Resources'; ModuleVersion = '7.0.0' }, @{ ModuleName = 'Az.KeyVault'; ModuleVersion = '6.0.0' }
<#
.SYNOPSIS
    Removes an RDG installation: tenant grants and apps, every Azure resource, the state and the
    pipeline's app registration.
.DESCRIPTION
    One command instead of tofu destroy plus the manual steps. Run it signed in to Azure
    (Connect-AzAccount) as Owner of the subscription; the tenant step signs in to Graph and
    Exchange like bootstrap stage 2 and needs the same roles. In order:
      1. Initialize-RdgTenant.ps1 -Remove: Graph and Exchange grants, the Exchange role group and
         registration, the sign-in app (skip with -SkipTenant),
      2. the budget and the resource group rg-<prefix>-<env> with every RDG resource (deleting the
         group removes everything in it, including what OpenTofu protects with prevent_destroy),
      3. the resource group rg-<prefix>-<env>-bootstrap with the state (keep with -KeepBootstrap),
      4. the pipeline's app registration (keep with -KeepPipelineApp).
    It asks before each step; -Force skips the questions, -WhatIf shows the plan only.
    Left behind on purpose (printed at the end): soft-deleted Key Vaults (purge protection, 90
    days; a reinstall with the same names recovers them), the Admin and Reader groups and the
    groups RDG managed, and the Azure DevOps service connection and environment.
.EXAMPLE
    ./bootstrap/Uninstall-Rdg.ps1 -SubscriptionId $sub -SettingsFile ./settings/eval.tfvars -WhatIf
.EXAMPLE
    ./bootstrap/Uninstall-Rdg.ps1 -SubscriptionId $sub -SettingsFile ./settings/eval.tfvars
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string] $SubscriptionId,

    [string] $SettingsFile,

    [ValidatePattern('^[a-z][a-z0-9]{1,5}$')]
    [string] $NamePrefix,

    [ValidatePattern('^[a-z0-9]{2,7}$')]
    [string] $Environment,

    # Leave the tenant as it is (grants, Exchange role group, sign-in app).
    [switch] $SkipTenant,

    # Tenant step without Exchange Online (as for stage 2).
    [switch] $SkipExchange,

    # Keep the OpenTofu state and its Key Vault.
    [switch] $KeepBootstrap,

    # Keep the pipeline's app registration (for example when Azure DevOps created it).
    [switch] $KeepPipelineApp,

    # Don't ask before each step.
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RdgBootstrap.psm1') -Force
if ($Force -and -not $WhatIfPreference) { $ConfirmPreference = 'None' }

function Write-Step {
    param([string] $Message)
    Write-Information -MessageData "-- $Message" -InformationAction Continue
}

$settings = if ($SettingsFile) { Read-RdgSettingsFile -Path $SettingsFile } else { @{} }
if (-not $NamePrefix) { $NamePrefix = if ($settings['name_prefix']) { [string]$settings.name_prefix } else { 'rdg' } }
if (-not $Environment) { $Environment = if ($settings['environment']) { [string]$settings.environment } else { 'prod' } }
$names = Get-RdgResourceName -NamePrefix $NamePrefix -Environment $Environment -SubscriptionId $SubscriptionId
$plan = Get-RdgUninstallPlan -Names $names -SkipTenant:$SkipTenant -KeepBootstrap:$KeepBootstrap -KeepPipelineApp:$KeepPipelineApp

$context = Get-AzContext
if (-not $context) { throw 'Not signed in to Azure. Run Connect-AzAccount first.' }
if ($context.Subscription.Id -ne $SubscriptionId) { $context = Set-AzContext -Subscription $SubscriptionId }

Write-Information -InformationAction Continue -MessageData "Uninstalling RDG $NamePrefix-$Environment from subscription $SubscriptionId ($($context.Subscription.Name)):"
foreach ($step in $plan.Steps) { Write-Information -MessageData "  $($step.Step). $($step.Target): $($step.Action)" -InformationAction Continue }

# --- 1. Tenant (needs the identities, so before the resource group goes)
if (-not $SkipTenant -and $PSCmdlet.ShouldProcess('tenant', 'Remove RDG grants, Exchange role group and sign-in app')) {
    Write-Step 'Tenant'
    $tenant = @{ SubscriptionId = $SubscriptionId; NamePrefix = $NamePrefix; Environment = $Environment; Remove = $true; Confirm = $false }
    if ($SettingsFile) { $tenant.SettingsFile = $SettingsFile }
    if ($SkipExchange) { $tenant.SkipExchange = $true }
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-RdgTenant.ps1') @tenant
}

# --- 2. RDG resources
$group = Get-AzResourceGroup -Name $names.ResourceGroup -ErrorAction SilentlyContinue
if ($group -and $PSCmdlet.ShouldProcess($names.ResourceGroup, 'Delete the resource group and every RDG resource in it')) {
    Write-Step "Resource group $($names.ResourceGroup)"
    # The budget lives on the resource group's scope; remove it explicitly.
    $budget = "$($group.ResourceId)/providers/Microsoft.Consumption/budgets/budget-$NamePrefix-$Environment`?api-version=2023-05-01"
    $response = Invoke-AzRestMethod -Method DELETE -Path $budget
    if ($response.StatusCode -ge 400 -and $response.StatusCode -ne 404) { Write-Warning -Message "Deleting the budget answered HTTP $($response.StatusCode); remove it in Cost Management." }
    [void](Remove-AzResourceGroup -Name $names.ResourceGroup -Force)
} elseif (-not $group) {
    Write-Step "Resource group $($names.ResourceGroup) doesn't exist"
}

# --- 3. State
if (-not $KeepBootstrap) {
    $bootstrap = Get-AzResourceGroup -Name $names.BootstrapGroup -ErrorAction SilentlyContinue
    if ($bootstrap -and $PSCmdlet.ShouldProcess($names.BootstrapGroup, 'Delete the resource group with the OpenTofu state')) {
        Write-Step "Resource group $($names.BootstrapGroup)"
        [void](Remove-AzResourceGroup -Name $names.BootstrapGroup -Force)
    }
}

# --- 4. Pipeline app registration (only the one stage 1 created, found by its name)
if (-not $KeepPipelineApp) {
    $apps = @(Get-AzADApplication -DisplayName $names.PipelineApp -ErrorAction SilentlyContinue)
    foreach ($app in $apps) {
        if ($PSCmdlet.ShouldProcess($names.PipelineApp, "Delete app registration $($app.AppId)")) {
            Write-Step "App registration $($names.PipelineApp)"
            Remove-AzADApplication -ObjectId $app.Id
        }
    }
}

# --- Left behind
$vaultNames = @($names.AppKeyVault, $names.StateKeyVault)
$removed = @(Get-AzKeyVault -InRemovedState -ErrorAction SilentlyContinue | Where-Object { $_.VaultName -in $vaultNames })
Write-Information -InformationAction Continue -MessageData "`nLeft in place:"
foreach ($line in $plan.Kept) { Write-Information -MessageData "  - $line" -InformationAction Continue }
foreach ($vault in $removed) {
    Write-Information -MessageData "  - soft-deleted: $($vault.VaultName), purged by Azure on $($vault.ScheduledPurgeDate)" -InformationAction Continue
}
