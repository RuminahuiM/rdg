#Requires -Version 7.4
<#
.SYNOPSIS
    Helpers for the RDG bootstrap scripts (Initialize-RdgAzure.ps1, Initialize-RdgTenant.ps1,
    New-RdgTestUsers.ps1).
.DESCRIPTION
    Names, settings file parsing, the permission sets per access mode and the reconcile logic
    (what to add, what to remove) live here so they can be tested without a tenant
    (tests/Bootstrap). Functions that call Microsoft Graph take the call as a script block
    (-Invoke), which defaults to Invoke-MgGraphRequest.
#>

Set-StrictMode -Version Latest

# Well-known application IDs.
$script:GraphAppId = '00000003-0000-0000-c000-000000000000'
$script:ExchangeAppId = '00000002-0000-0ff1-ce00-000000000000'

#region Names and settings

function Get-RdgNameSuffix {
    <#
    .SYNOPSIS
        The 4-character suffix of globally unique names, derived from the subscription ID.
    .DESCRIPTION
        Same as OpenTofu's substr(sha1(lower(subscription_id)), 0, 4) in infra/main.tf.
    .EXAMPLE
        Get-RdgNameSuffix -SubscriptionId '11111111-2222-3333-4444-555555555555'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string] $SubscriptionId
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($SubscriptionId.ToLowerInvariant())
    $hash = [System.Security.Cryptography.SHA1]::HashData($bytes)
    ([System.Convert]::ToHexString($hash)).ToLowerInvariant().Substring(0, 4)
}

function Get-RdgResourceName {
    <#
    .SYNOPSIS
        Every resource name of one installation, as OpenTofu and stage 1 create them.
    .EXAMPLE
        Get-RdgResourceName -NamePrefix rdg -Environment prod -SubscriptionId $id
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z][a-z0-9]{1,5}$')]
        [string] $NamePrefix,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9]{2,7}$')]
        [string] $Environment,

        [Parameter(Mandatory)]
        [string] $SubscriptionId
    )

    $suffix = Get-RdgNameSuffix -SubscriptionId $SubscriptionId
    $base = "$NamePrefix-$Environment"
    @{
        Suffix               = $suffix
        ResourceGroup        = "rg-$base"
        BootstrapGroup       = "rg-$base-bootstrap"
        StateStorageAccount  = "st$NamePrefix$($Environment)bs$suffix"
        StateContainer       = 'tfstate'
        StateKey             = "rdg-$Environment.tfstate"
        StateKeyVault        = "kv-$base-bs$suffix"
        StateKeyName         = 'rdg-state'
        AppKeyVault          = "kv-$base-$suffix"
        SignInCertificate    = 'rdg-signin'
        EngineIdentity       = "id-$NamePrefix-engine-$Environment"
        ApiIdentity          = "id-$NamePrefix-api-$Environment"
        MaintenanceIdentity  = "id-$NamePrefix-maintenance-$Environment"
        AutomationAccount    = "aa-$base"
        StaticWebApp         = "stapp-$base"
        FunctionApp          = "func-$base-$suffix"
        FunctionsStorage     = "st$NamePrefix$Environment$suffix"
        CosmosAccount        = "cosmos-$base-$suffix"
        PipelineApp          = "RDG pipeline ($base)"
        SignInApp            = "RDG sign-in ($base)"
        ExchangeRoleGroup    = "RDG Engine ($base)"
        ExchangeSpName       = "RDG engine ($base)"
        AdminGroup           = 'RDG Admins'
        ReaderGroup          = 'RDG Readers'
        MarkerExtensionShort = 'rdgDefinitionId'
    }
}

function Read-RdgSettingsFile {
    <#
    .SYNOPSIS
        Reads the simple values of an RDG settings file (.tfvars).
    .DESCRIPTION
        Understands the shapes the settings file uses: key = "string", key = number,
        key = true/false and key = ["a", "b"]. Comments (#, //) and maps such as tags are
        skipped. Not a general HCL parser.
    .EXAMPLE
        $settings = Read-RdgSettingsFile -Path ./examples/contoso.tfvars
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "settings file not found: $Path" }
    $settings = @{}
    $depth = 0
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = ($raw -replace '\s+(#|//).*$', '').Trim()
        if (-not $line -or $line.StartsWith('#') -or $line.StartsWith('//')) { continue }
        if ($depth -gt 0) {
            $depth += ([regex]::Matches($line, '[\{\[]').Count - [regex]::Matches($line, '[\}\]]').Count)
            continue
        }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$') { continue }
        $key = $Matches[1]
        $value = $Matches[2].Trim()
        if ($value -match '^"(.*)"$') {
            $settings[$key] = $Matches[1] -replace '\\"', '"'
        } elseif ($value -match '^-?\d+(\.\d+)?$') {
            $settings[$key] = [double]$value
        } elseif ($value -in @('true', 'false')) {
            $settings[$key] = $value -eq 'true'
        } elseif ($value -match '^\[(.*)\]$') {
            $settings[$key] = [string[]]@([regex]::Matches($Matches[1], '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
        } else {
            # A map or a list spread over several lines: skip until it closes.
            $depth = [regex]::Matches($value, '[\{\[]').Count - [regex]::Matches($value, '[\}\]]').Count
        }
    }
    $settings
}

#endregion

#region Permissions

function Get-RdgGraphPermission {
    <#
    .SYNOPSIS
        Microsoft Graph application permissions per identity (Identity and Access design).
    .DESCRIPTION
        Returns a hashtable engine/api/maintenance -> permission names. A read-only installation
        gives the engine read permissions only. Without -AccessMode, returns every permission
        RDG ever grants to that identity, which is what a rerun may remove.
    .EXAMPLE
        (Get-RdgGraphPermission -AccessMode read-only).engine
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateSet('read-only', 'read-write', 'all')]
        [string] $AccessMode = 'all'
    )

    $engineRead = @('User.Read.All', 'GroupMember.Read.All')
    $engineWrite = @('User.Read.All', 'GroupMember.ReadWrite.All', 'Group.Create', 'Group.ReadWrite.All')
    $engine = switch ($AccessMode) {
        'read-only' { $engineRead }
        'read-write' { $engineWrite }
        default { @($engineRead + $engineWrite | Select-Object -Unique) }
    }
    @{
        engine      = [string[]]$engine
        api         = [string[]]@('User.Read.All', 'GroupMember.Read.All')
        maintenance = [string[]]@('Application.ReadWrite.OwnedBy')
    }
}

function Get-RdgExchangeRole {
    <#
    .SYNOPSIS
        Exchange management roles of the "RDG Engine" role group for an access mode.
    .EXAMPLE
        Get-RdgExchangeRole -AccessMode read-write
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('read-only', 'read-write')]
        [string] $AccessMode
    )

    if ($AccessMode -eq 'read-write') {
        [string[]]@('Distribution Groups', 'Security Group Creation and Membership', 'View-Only Recipients')
    } else {
        [string[]]@('View-Only Recipients')
    }
}

function Get-RdgPipelineRole {
    <#
    .SYNOPSIS
        Azure roles OpenTofu assigns, which the pipeline's conditioned RBAC Administrator may grant.
    .DESCRIPTION
        Must match the azurerm_role_assignment resources in infra/modules. The names are for
        messages; the condition uses the IDs.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    [ordered]@{
        'Key Vault Certificate User'    = 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba'
        'Automation Job Operator'       = '4fe576fe-1146-4730-92eb-48519fa6bf9f'
        'Automation Runbook Operator'   = '5fb5aef8-1081-4b8e-bb16-9d5d0385bab5'
        'Storage Blob Data Owner'       = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
        'Storage Blob Data Contributor' = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    }
}

function Get-RdgRoleAssignmentCondition {
    <#
    .SYNOPSIS
        ABAC condition that limits a Role Based Access Control Administrator to some roles.
    .DESCRIPTION
        Allows creating and deleting role assignments only for the given role definition IDs
        (condition version 2.0), so the pipeline can't grant Owner or more rights to itself.
    .EXAMPLE
        Get-RdgRoleAssignmentCondition -RoleDefinitionId (Get-RdgPipelineRole).Values
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]] $RoleDefinitionId
    )

    foreach ($id in $RoleDefinitionId) {
        if ($id -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { throw "not a role definition ID: $id" }
    }
    $ids = ($RoleDefinitionId | ForEach-Object { $_.ToLowerInvariant() }) -join ', '
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR " +
    "(@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$ids})) AND " +
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR " +
    "(@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$ids}))"
}

function Get-RdgAppRoleChange {
    <#
    .SYNOPSIS
        Which app role assignments to add and which to remove.
    .DESCRIPTION
        Current: the identity's assignments on one resource (objects with id and appRoleId).
        Desired: app role IDs it should hold. Managed: app role IDs RDG may remove; assignments
        outside that set are left alone, so grants made by someone else survive a rerun.
    .EXAMPLE
        Get-RdgAppRoleChange -Current $assignments -Desired $want -Managed $all
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Current = @(),

        [AllowEmptyCollection()]
        [string[]] $Desired = @(),

        [AllowEmptyCollection()]
        [string[]] $Managed = @()
    )

    $held = [string[]]@($Current | ForEach-Object { [string]$_.appRoleId })
    [pscustomobject]@{
        Add    = [string[]]@($Desired | Where-Object { $held -notcontains $_ } | Select-Object -Unique)
        Remove = [object[]]@($Current | Where-Object { $Managed -contains [string]$_.appRoleId -and $Desired -notcontains [string]$_.appRoleId })
    }
}

#endregion

#region Sign-in app

function Get-RdgSignInAppBody {
    <#
    .SYNOPSIS
        The application object of the RDG sign-in app (create or update body).
    .DESCRIPTION
        Single tenant, web redirect URI of the Static Web App, ID tokens on, app roles Admin and
        Reader for users and groups, delegated User.Read and the OpenID scopes. Existing app role
        IDs are kept so assignments survive a rerun.
    .EXAMPLE
        Get-RdgSignInAppBody -DisplayName 'RDG sign-in (rdg-prod)' -RedirectUri $uri -GraphScope $scopes
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $DisplayName,

        [AllowEmptyCollection()]
        [string[]] $RedirectUri = @(),

        # Graph delegated scope name -> ID (User.Read, openid, profile, email).
        [Parameter(Mandatory)]
        [hashtable] $GraphScope,

        # The app's current appRoles, if it exists.
        [AllowEmptyCollection()]
        [object[]] $ExistingAppRole = @()
    )

    $roles = foreach ($role in @(
            @{ Value = 'Admin'; Name = 'RDG Admin'; Description = 'Can change RDG groups, rules and settings.' }
            @{ Value = 'Reader'; Name = 'RDG Reader'; Description = 'Can view RDG groups, rules, activity and audit.' }
        )) {
        $existing = @($ExistingAppRole | Where-Object { $null -ne $_ -and [string]$_.value -eq $role.Value }) | Select-Object -First 1
        [ordered]@{
            id                 = if ($existing) { [string]$existing.id } else { [guid]::NewGuid().ToString() }
            value              = $role.Value
            displayName        = $role.Name
            description        = $role.Description
            allowedMemberTypes = @('User')
            isEnabled          = $true
        }
    }
    foreach ($name in @('User.Read', 'openid', 'profile', 'email')) {
        if (-not $GraphScope.ContainsKey($name)) { throw "the Graph scope $name is missing" }
    }

    @{
        displayName            = $DisplayName
        signInAudience         = 'AzureADMyOrg'
        tags                   = @('rdg')
        appRoles               = @($roles)
        web                    = @{
            redirectUris          = @($RedirectUri)
            implicitGrantSettings = @{ enableIdTokenIssuance = $true; enableAccessTokenIssuance = $false }
        }
        requiredResourceAccess = @(
            @{
                resourceAppId  = $script:GraphAppId
                resourceAccess = @(
                    foreach ($name in @('User.Read', 'openid', 'profile', 'email')) {
                        @{ id = [string]$GraphScope[$name]; type = 'Scope' }
                    }
                )
            }
        )
    }
}

function Get-RdgKeyCredentialPatch {
    <#
    .SYNOPSIS
        The keyCredentials body that adds a certificate to the sign-in app, or $null.
    .DESCRIPTION
        Existing: the app's keyCredentials read with $select=keyCredentials (so they carry their
        key). Keeps every key that hasn't expired and adds the certificate when its thumbprint
        isn't there yet. Returns $null when nothing changes.
    .EXAMPLE
        Get-RdgKeyCredentialPatch -Existing $app.keyCredentials -CertificateBase64 $cer
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Existing = @(),

        [Parameter(Mandatory)]
        [string] $CertificateBase64,

        [DateTimeOffset] $Now = [DateTimeOffset]::UtcNow
    )

    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Convert]::FromBase64String($CertificateBase64))
    $keep = [System.Collections.Generic.List[object]]::new()
    $present = $false
    $removed = $false
    foreach ($entry in @($Existing | Where-Object { $null -ne $_ })) {
        $end = if ($entry.endDateTime) { [DateTimeOffset]$entry.endDateTime } else { $null }
        if ($end -and $end -le $Now) { $removed = $true; continue }
        if (-not $entry.key) { throw "the app key $($entry.keyId) came back without its value; read it with `$select=keyCredentials" }
        $thumbprint = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Convert]::FromBase64String([string]$entry.key)).Thumbprint
        if ($thumbprint -eq $certificate.Thumbprint) { $present = $true }
        $keep.Add([ordered]@{
                keyId       = [string]$entry.keyId
                type        = [string]$entry.type
                usage       = [string]$entry.usage
                key         = [string]$entry.key
                displayName = [string]$entry.displayName
            })
    }
    if ($present -and -not $removed) { return $null }
    if (-not $present) {
        $keep.Add([ordered]@{
                type        = 'AsymmetricX509Cert'
                usage       = 'Verify'
                key         = $CertificateBase64
                displayName = $certificate.Subject
            })
    }
    @{ keyCredentials = @($keep) }
}

#endregion

#region Graph calls

function Invoke-RdgGraphRequest {
    <#
    .SYNOPSIS
        One Microsoft Graph call through the given invoker, returning every page of a list.
    .DESCRIPTION
        Invoke defaults to Invoke-MgGraphRequest (Microsoft.Graph.Authentication). URIs are
        relative to https://graph.microsoft.com/v1.0.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [object] $Body,

        [switch] $All,

        [scriptblock] $Invoke = {
            param($Method, $Uri, $Body)
            $request = @{ Method = $Method; Uri = $Uri; OutputType = 'PSObject'; ErrorAction = 'Stop' }
            if ($null -ne $Body) { $request.Body = $Body; $request.ContentType = 'application/json' }
            Invoke-MgGraphRequest @request
        }
    )

    $full = if ($Uri -match '^https://') { $Uri } else { "https://graph.microsoft.com/v1.0$Uri" }
    $payload = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 10 -Compress } else { $null }
    $response = & $Invoke $Method $full $payload
    if (-not $All) { return $response }
    $items = [System.Collections.Generic.List[object]]::new()
    while ($null -ne $response) {
        foreach ($item in @($response.value)) { if ($null -ne $item) { $items.Add($item) } }
        $next = if ($response.PSObject.Properties['@odata.nextLink']) { $response.'@odata.nextLink' } else { $null }
        $response = if ($next) { & $Invoke 'GET' $next $null } else { $null }
    }
    $items.ToArray()
}

function Get-RdgServicePrincipal {
    <#
    .SYNOPSIS
        A service principal by its application ID, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $AppId,

        [scriptblock] $Invoke
    )

    $filter = [uri]::EscapeDataString("appId eq '$AppId'")
    $call = @{ Method = 'GET'; Uri = "/servicePrincipals?`$filter=$filter&`$select=id,appId,displayName,appRoles,oauth2PermissionScopes"; All = $true }
    if ($Invoke) { $call.Invoke = $Invoke }
    @(Invoke-RdgGraphRequest @call) | Select-Object -First 1
}

function Set-RdgAppRoleGrant {
    <#
    .SYNOPSIS
        Makes an identity hold exactly the wanted application permissions of one API.
    .DESCRIPTION
        Adds missing app role assignments and removes ones RDG manages (Managed) that are no
        longer wanted. Permission names are resolved on the resource service principal.
        Returns what changed.
    .EXAMPLE
        Set-RdgAppRoleGrant -PrincipalId $engineSp -Resource $graphSp -Desired User.Read.All -Managed $all
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        # Object ID of the identity's service principal.
        [Parameter(Mandatory)]
        [string] $PrincipalId,

        # The resource service principal (id, appRoles).
        [Parameter(Mandatory)]
        [object] $Resource,

        [AllowEmptyCollection()]
        [string[]] $Desired = @(),

        [AllowEmptyCollection()]
        [string[]] $Managed = @(),

        [scriptblock] $Invoke
    )

    $roleId = @{}
    foreach ($role in @($Resource.appRoles)) { $roleId[[string]$role.value] = [string]$role.id }
    foreach ($name in @($Desired) + @($Managed)) {
        if (-not $roleId.ContainsKey($name)) { throw "the permission $name doesn't exist on $($Resource.displayName)" }
    }
    $graph = @{}
    if ($Invoke) { $graph.Invoke = $Invoke }

    $current = @(Invoke-RdgGraphRequest @graph -Method GET -Uri "/servicePrincipals/$PrincipalId/appRoleAssignments" -All |
            Where-Object { [string]$_.resourceId -eq [string]$Resource.id })
    $change = Get-RdgAppRoleChange -Current $current `
        -Desired ([string[]]@($Desired | ForEach-Object { $roleId[$_] })) `
        -Managed ([string[]]@($Managed | ForEach-Object { $roleId[$_] }))
    $names = @{}
    foreach ($key in $roleId.Keys) { $names[$roleId[$key]] = $key }

    $added = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $change.Add) {
        if ($PSCmdlet.ShouldProcess($PrincipalId, "Grant $($names[$id])")) {
            $body = @{ principalId = $PrincipalId; resourceId = [string]$Resource.id; appRoleId = $id }
            [void](Invoke-RdgGraphRequest @graph -Method POST -Uri "/servicePrincipals/$PrincipalId/appRoleAssignments" -Body $body)
            $added.Add($names[$id])
        }
    }
    foreach ($assignment in $change.Remove) {
        $name = $names[[string]$assignment.appRoleId]
        if ($PSCmdlet.ShouldProcess($PrincipalId, "Remove $name")) {
            [void](Invoke-RdgGraphRequest @graph -Method DELETE -Uri "/servicePrincipals/$PrincipalId/appRoleAssignments/$($assignment.id)")
            $removed.Add($name)
        }
    }
    [pscustomobject]@{ Added = $added.ToArray(); Removed = $removed.ToArray() }
}

#endregion

#region Test users

function Get-RdgTestUserData {
    <#
    .SYNOPSIS
        Invented test users for a test tenant (Infrastructure design, "Testing before HEKS").
    .DESCRIPTION
        Deterministic: the same Count gives the same users, so reruns only add what is missing.
        Every value is invented. Every fifth user is disabled.
    .EXAMPLE
        Get-RdgTestUserData -Count 15 -Domain contoso.onmicrosoft.com
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 50)]
        [int] $Count = 15,

        [Parameter(Mandatory)]
        [string] $Domain
    )

    $departments = @('IT', 'Finance', 'Programmes', 'Communication', 'HR')
    $cities = @('Zurich', 'Bern', 'Lausanne', 'Geneva')
    $titles = @('Officer', 'Manager', 'Coordinator', 'Specialist')
    $countries = @('CH', 'CH', 'CH', 'DE')
    for ($i = 1; $i -le $Count; $i++) {
        $n = '{0:d2}' -f $i
        $attributes = [ordered]@{}
        for ($a = 1; $a -le 15; $a++) { $attributes["extensionAttribute$a"] = $null }
        $attributes.extensionAttribute1 = @('Staff', 'Staff', 'Volunteer', 'Intern')[$i % 4]
        $attributes.extensionAttribute2 = "CC-$((($i % 3) + 1) * 100)"
        if ($i % 2 -eq 0) { $attributes.extensionAttribute3 = 'Board' }
        $attributes.extensionAttribute15 = 'rdg-test'
        [pscustomobject]@{
            DisplayName         = "RDG Test $n"
            MailNickname        = "rdgtest$n"
            UserPrincipalName   = "rdgtest$n@$Domain"
            AccountEnabled      = ($i % 5) -ne 0
            Department          = $departments[$i % $departments.Count]
            JobTitle            = $titles[$i % $titles.Count]
            City                = $cities[$i % $cities.Count]
            Country             = $countries[$i % $countries.Count]
            UsageLocation       = $countries[$i % $countries.Count]
            EmployeeId          = "T$((1000 + $i))"
            ExtensionAttributes = $attributes
        }
    }
}

#endregion

#region Uninstall

function Get-RdgUninstallPlan {
    <#
    .SYNOPSIS
        What Uninstall-Rdg.ps1 removes, in order, and what it leaves.
    .DESCRIPTION
        Returns one entry per step (Step, Target, Action) plus Kept: the things that stay and why.
        The tenant step comes first because it finds the identities through the resource group.
    .EXAMPLE
        Get-RdgUninstallPlan -Names (Get-RdgResourceName -NamePrefix rdg -Environment eval -SubscriptionId $id)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Names,

        [switch] $SkipTenant,

        [switch] $KeepBootstrap,

        [switch] $KeepPipelineApp
    )

    $steps = [System.Collections.Generic.List[object]]::new()
    $add = { param($target, $action) $steps.Add([pscustomobject]@{ Step = $steps.Count + 1; Target = $target; Action = $action }) }
    if (-not $SkipTenant) {
        & $add 'Tenant' "Initialize-RdgTenant.ps1 -Remove: Graph and Exchange grants, Exchange role group '$($Names.ExchangeRoleGroup)', app '$($Names.SignInApp)'"
    }
    & $add $Names.ResourceGroup 'Delete the budget, then the resource group with every RDG resource'
    if (-not $KeepBootstrap) {
        & $add $Names.BootstrapGroup 'Delete the resource group with the OpenTofu state and its key'
    }
    if (-not $KeepPipelineApp) {
        & $add $Names.PipelineApp 'Delete the app registration of the pipeline'
    }
    $kept = [System.Collections.Generic.List[string]]::new()
    $kept.Add("Key Vaults $($Names.AppKeyVault) and $($Names.StateKeyVault): soft-deleted for 90 days (purge protection); a reinstall with the same names recovers them")
    $kept.Add("Groups '$($Names.AdminGroup)' and '$($Names.ReaderGroup)', if stage 2 created them, and every group RDG managed, with its last members")
    $kept.Add('Azure DevOps: the service connection, the environment and the pipeline (delete them there)')
    if ($SkipTenant) { $kept.Add('Tenant grants, Exchange role group and sign-in app (-SkipTenant)') }
    if ($KeepBootstrap) { $kept.Add("$($Names.BootstrapGroup) (-KeepBootstrap): the state still lists the deleted resources; delete the state blob before a reinstall") }
    if ($KeepPipelineApp) { $kept.Add("$($Names.PipelineApp) (-KeepPipelineApp)") }
    [pscustomobject]@{ Steps = $steps.ToArray(); Kept = $kept.ToArray() }
}

#endregion

Export-ModuleMember -Function @(
    'Get-RdgNameSuffix'
    'Get-RdgResourceName'
    'Read-RdgSettingsFile'
    'Get-RdgGraphPermission'
    'Get-RdgExchangeRole'
    'Get-RdgPipelineRole'
    'Get-RdgRoleAssignmentCondition'
    'Get-RdgAppRoleChange'
    'Get-RdgSignInAppBody'
    'Get-RdgKeyCredentialPatch'
    'Invoke-RdgGraphRequest'
    'Get-RdgServicePrincipal'
    'Set-RdgAppRoleGrant'
    'Get-RdgTestUserData'
    'Get-RdgUninstallPlan'
)
