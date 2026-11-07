#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }, @{ ModuleName = 'Az.Resources'; ModuleVersion = '7.0.0' }, @{ ModuleName = 'Az.KeyVault'; ModuleVersion = '6.0.0' }, @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.20.0' }
<#
.SYNOPSIS
    RDG bootstrap stage 2: the tenant side (Graph permissions, Exchange, sign-in app, certificate).
.DESCRIPTION
    Run by a person after the first pipeline run, signed in to Azure (Connect-AzAccount) with
    Owner or User Access Administrator on the RDG resource group, and able to sign in to Graph
    and Exchange as Global Administrator, or as Privileged Role + Application + Exchange
    Administrator. Idempotent: a rerun adds what is missing and, when access_mode changed,
    removes the write grants. It
      1. grants the Microsoft Graph application permissions of engine, api and maintenance
         (read-only installations: the engine gets read permissions only),
      2. grants Exchange.ManageAsApp to the engine, registers it in Exchange Online and creates
         the role group "RDG Engine (<prefix>-<env>)" with the roles of the access mode,
      3. creates the "RDG sign-in" app registration (single tenant, app roles Admin and Reader,
         assignment required, admin consent for User.Read), makes the maintenance identity its
         owner and registers the marker extension property rdgDefinitionId for groups,
      4. creates the sign-in certificate in the app Key Vault (self-signed, 12 months, renewed
         60 days before expiry) and adds it to the app; you get Key Vault Certificates Officer
         for this step only,
      5. assigns Admin and Reader to admin_group_id and reader_group_id, or creates "RDG Admins"
         and "RDG Readers",
      6. prints signin_client_id for the settings file.
    -Remove reverses 1 to 3 and the role assignments of 5. Groups and the certificate stay (the
    Key Vault goes with tofu destroy).
    Reference: Identity and Access design, Infrastructure design ("Bootstrap").
.PARAMETER SettingsFile
    The installation's settings file; name_prefix, environment, access_mode, tenant_domain,
    admin_group_id and reader_group_id are read from it. Explicit parameters win.
.PARAMETER SkipExchange
    Leaves out step 2's Exchange Online part, for a tenant without Exchange Online yet. Rerun
    without it once Exchange is there.
.EXAMPLE
    ./bootstrap/Initialize-RdgTenant.ps1 -SubscriptionId $sub -SettingsFile ./rdg-prod.tfvars
.EXAMPLE
    ./bootstrap/Initialize-RdgTenant.ps1 -SubscriptionId $sub -SettingsFile ./rdg-prod.tfvars -Remove
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string] $SubscriptionId,

    [string] $SettingsFile,

    [ValidatePattern('^[a-z][a-z0-9]{1,5}$')]
    [string] $NamePrefix,

    [ValidatePattern('^[a-z0-9]{2,7}$')]
    [string] $Environment,

    [ValidateSet('read-only', 'read-write')]
    [string] $AccessMode,

    [string] $TenantDomain,

    [string] $AdminGroupId,

    [string] $ReaderGroupId,

    [switch] $SkipExchange,

    # Required together with access_mode = read-write; without it the script refuses write grants.
    [switch] $AllowReadWrite,

    [switch] $Remove
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RdgBootstrap.psm1') -Force

function Write-Step {
    param([string] $Message)
    Write-Information -MessageData "-- $Message" -InformationAction Continue
}

function Invoke-WithRetry {
    # New service principals and role assignments take a while to replicate.
    param([scriptblock] $Action, [string] $What, [int] $Attempts = 12, [int] $DelaySeconds = 10)
    for ($i = 1; ; $i++) {
        try { return & $Action } catch {
            if ($i -ge $Attempts) { throw "$What failed after $Attempts attempts: $($_.Exception.Message)" }
            Write-Verbose -Message "$What not ready yet ($($_.Exception.Message)); retrying in $DelaySeconds s"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Get-Identity {
    # A user-assigned identity of the installation, or $null when it doesn't exist (yet or any more).
    param([string] $ResourceGroup, [string] $Name)
    $resource = Get-AzResource -ResourceGroupName $ResourceGroup -ResourceType 'Microsoft.ManagedIdentity/userAssignedIdentities' `
        -Name $Name -ExpandProperties -ErrorAction SilentlyContinue
    if (-not $resource) { return $null }
    [pscustomobject]@{ Name = $Name; PrincipalId = [string]$resource.Properties.principalId; ClientId = [string]$resource.Properties.clientId }
}

function Find-GraphObject {
    # The first object of a Graph collection matching a filter, or $null.
    param([string] $Collection, [string] $Filter, [string] $Select = 'id,displayName')
    $encoded = [uri]::EscapeDataString($Filter)
    @(Invoke-RdgGraphRequest -Method GET -Uri "/$Collection`?`$filter=$encoded&`$select=$Select" -All) | Select-Object -First 1
}

# --- Settings
$settings = if ($SettingsFile) { Read-RdgSettingsFile -Path $SettingsFile } else { @{} }
function Get-Setting {
    param([string] $Value, [string] $Key, [string] $Default)
    if ($Value) { return $Value }
    if ($settings.ContainsKey($Key) -and [string]$settings[$Key]) { return [string]$settings[$Key] }
    $Default
}
$NamePrefix = Get-Setting -Value $NamePrefix -Key 'name_prefix' -Default 'rdg'
$Environment = Get-Setting -Value $Environment -Key 'environment' -Default 'prod'
$AccessMode = Get-Setting -Value $AccessMode -Key 'access_mode' -Default 'read-only'
$TenantDomain = Get-Setting -Value $TenantDomain -Key 'tenant_domain' -Default ''
$AdminGroupId = Get-Setting -Value $AdminGroupId -Key 'admin_group_id' -Default ''
$ReaderGroupId = Get-Setting -Value $ReaderGroupId -Key 'reader_group_id' -Default ''
if ($AccessMode -notin @('read-only', 'read-write')) { throw "access_mode must be read-only or read-write, not '$AccessMode'" }
if ($AccessMode -eq 'read-write' -and -not $Remove -and -not $AllowReadWrite) {
    # A safety catch: write grants change what RDG can do in the tenant, so they need a second, explicit yes.
    throw 'access_mode is read-write: this grants the engine write access to groups. Add -AllowReadWrite to confirm.'
}
$names = Get-RdgResourceName -NamePrefix $NamePrefix -Environment $Environment -SubscriptionId $SubscriptionId

$context = Get-AzContext
if (-not $context) { throw 'Not signed in to Azure. Run Connect-AzAccount first.' }
if ($context.Subscription.Id -ne $SubscriptionId) { $context = Set-AzContext -Subscription $SubscriptionId }
$tenantId = $context.Tenant.Id

# --- Discover the installation
Write-Step "Installation $($names.ResourceGroup)"
$identity = @{
    engine      = Get-Identity -ResourceGroup $names.ResourceGroup -Name $names.EngineIdentity
    api         = Get-Identity -ResourceGroup $names.ResourceGroup -Name $names.ApiIdentity
    maintenance = Get-Identity -ResourceGroup $names.ResourceGroup -Name $names.MaintenanceIdentity
}
if (-not $Remove) {
    foreach ($key in $identity.Keys) {
        if (-not $identity[$key]) { throw "The identity $key of $($names.ResourceGroup) doesn't exist. Run the pipeline (tofu apply) first." }
    }
}

Connect-MgGraph -TenantId $tenantId -NoWelcome -Scopes @(
    'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All', 'Group.ReadWrite.All'
)
$graphSp = Get-RdgServicePrincipal -AppId '00000003-0000-0000-c000-000000000000'
if (-not $graphSp) { throw 'Could not read the Microsoft Graph service principal (sign-in not finished or no connection to graph.microsoft.com). Nothing was changed; run again.' }
$exchangeSp = Get-RdgServicePrincipal -AppId '00000002-0000-0ff1-ce00-000000000000'
if (-not $exchangeSp -and -not $SkipExchange) { throw 'Exchange Online has no service principal in this tenant. Use -SkipExchange until Exchange Online is set up.' }

# --- 1. Graph permissions
Write-Step "Graph permissions ($(if ($Remove) { 'remove' } else { $AccessMode }))"
$wanted = Get-RdgGraphPermission -AccessMode $AccessMode
$managed = Get-RdgGraphPermission
foreach ($key in @('engine', 'api', 'maintenance')) {
    if (-not $identity[$key]) { continue }
    $desired = if ($Remove) { [string[]]@() } else { $wanted[$key] }
    # -WhatIf is passed on explicitly: preference variables don't reach functions of a script module.
    $change = Set-RdgAppRoleGrant -PrincipalId $identity[$key].PrincipalId -Resource $graphSp -Desired $desired -Managed $managed[$key] -WhatIf:$WhatIfPreference
    foreach ($name in $change.Added) { Write-Information -MessageData "   $key + $name" -InformationAction Continue }
    foreach ($name in $change.Removed) { Write-Information -MessageData "   $key - $name" -InformationAction Continue }
}

# --- 2. Exchange
if ($exchangeSp -and $identity.engine) {
    $desired = if ($Remove) { [string[]]@() } else { [string[]]@('Exchange.ManageAsApp') }
    [void](Set-RdgAppRoleGrant -PrincipalId $identity.engine.PrincipalId -Resource $exchangeSp -Desired $desired -Managed 'Exchange.ManageAsApp' -WhatIf:$WhatIfPreference)
}
if (-not $SkipExchange) {
    Write-Step "Exchange role group $($names.ExchangeRoleGroup)"
    Import-Module -Name ExchangeOnlineManagement -MinimumVersion 3.10.1
    $exchange = @{ ShowBanner = $false }
    if ($TenantDomain) { $exchange.Organization = $TenantDomain }
    Connect-ExchangeOnline @exchange
    try {
        $group = Get-RoleGroup -Identity $names.ExchangeRoleGroup -ErrorAction SilentlyContinue
        $engineObjectId = if ($identity.engine) { $identity.engine.PrincipalId } else { $null }
        $exchangeSpObject = if ($engineObjectId) { Get-ServicePrincipal -Identity $engineObjectId -ErrorAction SilentlyContinue } else { $null }
        if ($Remove) {
            if ($group -and $PSCmdlet.ShouldProcess($names.ExchangeRoleGroup, 'Remove Exchange role group')) {
                Remove-RoleGroup -Identity $names.ExchangeRoleGroup -BypassSecurityGroupManagerCheck -Confirm:$false
            }
            if ($exchangeSpObject -and $PSCmdlet.ShouldProcess($names.ExchangeSpName, 'Remove Exchange service principal')) {
                Remove-ServicePrincipal -Identity $engineObjectId -Confirm:$false
            }
        } else {
            if (-not $exchangeSpObject -and $PSCmdlet.ShouldProcess($names.ExchangeSpName, 'Register the engine in Exchange Online')) {
                $exchangeSpObject = Invoke-WithRetry -What 'New-ServicePrincipal' -Action {
                    New-ServicePrincipal -AppId $identity.engine.ClientId -ObjectId $identity.engine.PrincipalId -DisplayName $names.ExchangeSpName
                }
            }
            $roles = Get-RdgExchangeRole -AccessMode $AccessMode
            if (-not $group -and $PSCmdlet.ShouldProcess($names.ExchangeRoleGroup, "Create role group ($($roles -join ', '))")) {
                $group = New-RoleGroup -Name $names.ExchangeRoleGroup -Roles $roles `
                    -Description 'RDG engine: the only member is the engine managed identity. Managed by bootstrap/Initialize-RdgTenant.ps1.'
            }
            if ($group) {
                $assigned = @(Get-ManagementRoleAssignment -RoleAssignee $names.ExchangeRoleGroup -Delegating $false -ErrorAction SilentlyContinue)
                $allRoles = Get-RdgExchangeRole -AccessMode read-write
                foreach ($role in $roles) {
                    if (@($assigned | Where-Object { [string]$_.Role -eq $role }).Count -eq 0 -and $PSCmdlet.ShouldProcess($names.ExchangeRoleGroup, "Add role $role")) {
                        [void](New-ManagementRoleAssignment -SecurityGroup $names.ExchangeRoleGroup -Role $role)
                    }
                }
                foreach ($assignment in $assigned) {
                    if ([string]$assignment.Role -in $allRoles -and [string]$assignment.Role -notin $roles -and
                        $PSCmdlet.ShouldProcess($names.ExchangeRoleGroup, "Remove role $($assignment.Role)")) {
                        Remove-ManagementRoleAssignment -Identity $assignment.Identity -Confirm:$false
                    }
                }
                if ($exchangeSpObject -and $PSCmdlet.ShouldProcess($names.ExchangeRoleGroup, 'Add the engine as member')) {
                    try {
                        Add-RoleGroupMember -Identity $names.ExchangeRoleGroup -Member $exchangeSpObject.Identity -BypassSecurityGroupManagerCheck -ErrorAction Stop
                    } catch {
                        # The message is localised (de: "ist bereits ein Mitglied"), so check the
                        # membership itself instead of the text.
                        $error0 = $_
                        $spKeys = @($exchangeSpObject.Identity, $exchangeSpObject.ObjectId, $exchangeSpObject.AppId, $engineObjectId) |
                            Where-Object { $_ } | ForEach-Object { [string]$_ }
                        $isMember = @(Get-RoleGroupMember -Identity $names.ExchangeRoleGroup -ResultSize Unlimited -ErrorAction SilentlyContinue |
                                Where-Object {
                                    $member = $_
                                    @('Identity', 'Name', 'ExternalDirectoryObjectId', 'Guid') | Where-Object {
                                        $member.PSObject.Properties[$_] -and [string]$member.$_ -in $spKeys
                                    }
                                }).Count -gt 0
                        if (-not $isMember -and $error0.Exception.Message -notmatch 'already a member') { throw $error0 }
                        Write-Step '   the engine is already a member'
                    }
                }
            }
        }
    } finally {
        Disconnect-ExchangeOnline -Confirm:$false
    }
}

# --- 3. Sign-in app
Write-Step "Sign-in app $($names.SignInApp)"
$app = Find-GraphObject -Collection 'applications' -Filter "displayName eq '$($names.SignInApp)'" -Select 'id,appId,displayName,appRoles,tags'
if ($Remove) {
    if ($app -and $PSCmdlet.ShouldProcess($names.SignInApp, 'Delete app registration (restorable for 30 days)')) {
        [void](Invoke-RdgGraphRequest -Method DELETE -Uri "/applications/$($app.id)")
    }
    Write-Information -InformationAction Continue -MessageData @"

Stage 2 removed. Left in place on purpose:
  - the Admin and Reader groups (they may be used elsewhere)
  - the sign-in certificate (it goes with the Key Vault on tofu destroy)
  - groups RDG managed, with their last members
"@
    return
}

$swa = Get-AzResource -ResourceGroupName $names.ResourceGroup -ResourceType 'Microsoft.Web/staticSites' -Name $names.StaticWebApp -ExpandProperties -ErrorAction SilentlyContinue
if (-not $swa) { throw "The Static Web App $($names.StaticWebApp) doesn't exist. Run the pipeline (tofu apply) first." }
$redirect = "https://$($swa.Properties.defaultHostname)/.auth/login/aad/callback"
$scopes = @{}
foreach ($scope in @($graphSp.oauth2PermissionScopes)) { $scopes[[string]$scope.value] = [string]$scope.id }
# @(...) around the if: an if that yields an empty array assigns $null, not an empty array.
$existingRoles = [object[]]@(if ($app) { @($app.appRoles) })
$body = Get-RdgSignInAppBody -DisplayName $names.SignInApp -RedirectUri $redirect -GraphScope $scopes -ExistingAppRole $existingRoles
if (-not $app) {
    if ($PSCmdlet.ShouldProcess($names.SignInApp, 'Create app registration')) {
        $app = Invoke-RdgGraphRequest -Method POST -Uri '/applications' -Body $body
    }
} elseif ($PSCmdlet.ShouldProcess($names.SignInApp, 'Update app registration')) {
    [void](Invoke-RdgGraphRequest -Method PATCH -Uri "/applications/$($app.id)" -Body $body)
}
if (-not $app) { return }   # -WhatIf on a first run: nothing below can be shown without the app.

$appSp = Invoke-WithRetry -What 'Sign-in service principal' -Action {
    $sp = Get-RdgServicePrincipal -AppId $app.appId
    if (-not $sp) {
        $sp = Invoke-RdgGraphRequest -Method POST -Uri '/servicePrincipals' -Body @{
            appId = $app.appId; appRoleAssignmentRequired = $true; tags = @('WindowsAzureActiveDirectoryIntegratedApp')
        }
    }
    $sp
}
[void](Invoke-RdgGraphRequest -Method PATCH -Uri "/servicePrincipals/$($appSp.id)" -Body @{ appRoleAssignmentRequired = $true })

# The maintenance identity owns the app, so Application.ReadWrite.OwnedBy reaches this app only.
$owners = @(Invoke-RdgGraphRequest -Method GET -Uri "/applications/$($app.id)/owners?`$select=id" -All)
if (@($owners | Where-Object { [string]$_.id -eq $identity.maintenance.PrincipalId }).Count -eq 0 -and
    $PSCmdlet.ShouldProcess($names.SignInApp, 'Add the maintenance identity as owner')) {
    [void](Invoke-RdgGraphRequest -Method POST -Uri "/applications/$($app.id)/owners/`$ref" -Body @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($identity.maintenance.PrincipalId)"
        })
}

# Admin consent for the delegated scopes, so nobody is asked at first sign-in.
$consentScope = 'User.Read openid profile email'
$grant = Find-GraphObject -Collection 'oauth2PermissionGrants' -Filter "clientId eq '$($appSp.id)' and consentType eq 'AllPrincipals' and resourceId eq '$($graphSp.id)'" -Select 'id,resourceId,scope'
if (-not $grant -and $PSCmdlet.ShouldProcess($names.SignInApp, "Admin consent: $consentScope")) {
    [void](Invoke-RdgGraphRequest -Method POST -Uri '/oauth2PermissionGrants' -Body @{
            clientId = $appSp.id; consentType = 'AllPrincipals'; resourceId = $graphSp.id; scope = $consentScope
        })
} elseif ($grant -and [string]$grant.scope -ne $consentScope -and $PSCmdlet.ShouldProcess($names.SignInApp, "Admin consent: $consentScope")) {
    [void](Invoke-RdgGraphRequest -Method PATCH -Uri "/oauth2PermissionGrants/$($grant.id)" -Body @{ scope = $consentScope })
}

# Marker extension property for groups: extension_<appId without dashes>_rdgDefinitionId.
$markerName = "extension_$(([string]$app.appId).Replace('-', '').ToLowerInvariant())_$($names.MarkerExtensionShort)"
$extensions = @(Invoke-RdgGraphRequest -Method GET -Uri "/applications/$($app.id)/extensionProperties" -All)
if (@($extensions | Where-Object { [string]$_.name -eq $markerName }).Count -eq 0 -and
    $PSCmdlet.ShouldProcess($names.SignInApp, "Register extension property $markerName")) {
    [void](Invoke-RdgGraphRequest -Method POST -Uri "/applications/$($app.id)/extensionProperties" -Body @{
            name = $names.MarkerExtensionShort; dataType = 'String'; targetObjects = @('Group')
        })
}

# --- 4. Certificate
Write-Step "Sign-in certificate $($names.SignInCertificate) in $($names.AppKeyVault)"
$vault = Get-AzKeyVault -VaultName $names.AppKeyVault -ResourceGroupName $names.ResourceGroup
$officer = 'a4417e6f-fecd-4de8-b567-7b0420556985'   # Key Vault Certificates Officer
$me = (Get-AzADUser -SignedIn).Id
$granted = $false
$hasOfficer = @(Get-AzRoleAssignment -ObjectId $me -Scope $vault.ResourceId -ErrorAction SilentlyContinue |
        Where-Object { $_.RoleDefinitionId -eq $officer -and $_.Scope -eq $vault.ResourceId }).Count -gt 0
if (-not $hasOfficer -and $PSCmdlet.ShouldProcess($names.AppKeyVault, 'Give yourself Key Vault Certificates Officer for this step')) {
    [void](New-AzRoleAssignment -ObjectId $me -ObjectType User -RoleDefinitionId $officer -Scope $vault.ResourceId)
    $granted = $true
}
try {
    # -WhatIf without the role: the certificate can't be read, so the step can't be previewed.
    if (-not $hasOfficer -and -not $granted) {
        Write-Step '(skipped: reading the certificate needs the role above, which -WhatIf does not grant)'
    } else {
        # A missing certificate returns nothing; 403 (the role assignment isn't active yet) is retried.
        $certificate = Invoke-WithRetry -What 'Reading the Key Vault' -Attempts 18 -Action {
            Get-AzKeyVaultCertificate -VaultName $names.AppKeyVault -Name $names.SignInCertificate -ErrorAction Stop
        }
        if (-not $certificate -and $PSCmdlet.ShouldProcess($names.SignInCertificate, 'Create self-signed certificate (12 months, auto-renew)')) {
            $policy = New-AzKeyVaultCertificatePolicy -SubjectName "CN=$($names.SignInApp)" -IssuerName Self -ValidityInMonths 12 `
                -RenewAtNumberOfDaysBeforeExpiry 60 -KeyType RSA -KeySize 2048 -SecretContentType 'application/x-pkcs12'
            [void](Invoke-WithRetry -What 'Creating the certificate' -Action {
                    Add-AzKeyVaultCertificate -VaultName $names.AppKeyVault -Name $names.SignInCertificate -CertificatePolicy $policy
                })
            $certificate = Invoke-WithRetry -What 'Waiting for the certificate' -Action {
                $created = Get-AzKeyVaultCertificate -VaultName $names.AppKeyVault -Name $names.SignInCertificate
                if (-not $created -or -not $created.Certificate) { throw 'still pending' }
                $created
            }
        }
        if ($certificate) {
            $cer = [System.Convert]::ToBase64String($certificate.Certificate.RawData)
            $current = Invoke-RdgGraphRequest -Method GET -Uri "/applications/$($app.id)?`$select=keyCredentials"
            $patch = Get-RdgKeyCredentialPatch -Existing ([object[]]@($current.keyCredentials)) -CertificateBase64 $cer
            if ($patch -and $PSCmdlet.ShouldProcess($names.SignInApp, "Add certificate $($certificate.Thumbprint)")) {
                [void](Invoke-RdgGraphRequest -Method PATCH -Uri "/applications/$($app.id)" -Body $patch)
            }
        }
    }
} finally {
    if ($granted) {
        Get-AzRoleAssignment -ObjectId $me -Scope $vault.ResourceId |
            Where-Object { $_.RoleDefinitionId -eq $officer -and $_.Scope -eq $vault.ResourceId } |
            Remove-AzRoleAssignment | Out-Null
    }
}

# --- 5. Admin and Reader
Write-Step 'Admin and Reader groups'
$app = Invoke-RdgGraphRequest -Method GET -Uri "/applications/$($app.id)?`$select=id,appId,appRoles"
$assignedTo = @(Invoke-RdgGraphRequest -Method GET -Uri "/servicePrincipals/$($appSp.id)/appRoleAssignedTo" -All)
$groupIds = @{}
foreach ($entry in @(
        @{ Role = 'Admin'; Id = $AdminGroupId; Name = $names.AdminGroup; Nickname = "$NamePrefix-$Environment-admins" }
        @{ Role = 'Reader'; Id = $ReaderGroupId; Name = $names.ReaderGroup; Nickname = "$NamePrefix-$Environment-readers" }
    )) {
    $groupId = $entry.Id
    if (-not $groupId) {
        $found = Find-GraphObject -Collection 'groups' -Filter "displayName eq '$($entry.Name)'"
        if ($found) {
            $groupId = [string]$found.id
        } elseif ($PSCmdlet.ShouldProcess($entry.Name, 'Create security group')) {
            $groupId = [string](Invoke-RdgGraphRequest -Method POST -Uri '/groups' -Body @{
                    displayName = $entry.Name; mailEnabled = $false; mailNickname = $entry.Nickname; securityEnabled = $true
                    description = "Members get the RDG $($entry.Role) role. Created by bootstrap/Initialize-RdgTenant.ps1."
                }).id
        }
    }
    if (-not $groupId) { continue }
    $groupIds[$entry.Role] = $groupId
    $roleId = [string](@($app.appRoles | Where-Object { [string]$_.value -eq $entry.Role }) | Select-Object -First 1).id
    $has = @($assignedTo | Where-Object { [string]$_.principalId -eq $groupId -and [string]$_.appRoleId -eq $roleId }).Count -gt 0
    if (-not $has -and $PSCmdlet.ShouldProcess($entry.Name, "Assign the $($entry.Role) role")) {
        try {
            [void](Invoke-RdgGraphRequest -Method POST -Uri "/servicePrincipals/$($appSp.id)/appRoleAssignedTo" -Body @{
                    principalId = $groupId; resourceId = $appSp.id; appRoleId = $roleId
                })
        } catch {
            # Assigning groups to app roles needs Microsoft Entra ID P1 or P2.
            Write-Warning -Message ("Assigning $($entry.Role) to group $groupId failed: $($_.Exception.Message) " +
                'Without Entra ID P1, assign users directly in Enterprise applications > RDG sign-in > Users and groups.')
        }
    }
}

# --- 6. Result
$result = [pscustomobject]@{
    SignInClientId  = [string]$app.appId
    AdminGroupId    = $groupIds['Admin']
    ReaderGroupId   = $groupIds['Reader']
    MarkerExtension = $markerName
    RedirectUri     = $redirect
}
Write-Information -InformationAction Continue -MessageData @"

Stage 2 done ($AccessMode).

Settings file:
  signin_client_id = "$($result.SignInClientId)"
  admin_group_id   = "$($result.AdminGroupId)"
  reader_group_id  = "$($result.ReaderGroupId)"

Next: run the pipeline again; it turns the sign-in on.
"@
$result
