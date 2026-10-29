# Building blocks for the end-to-end tests of Invoke-DgSync: an in-memory tenant (Custom
# directory), documents in the shape the API writes, and schema validation of what the engine
# stores. Dot-source in BeforeAll. All data is invented (contoso.org).

$script:KitRoot = Join-Path -Path $PSScriptRoot -ChildPath '../../..'

# Stable test IDs: user 1 -> 00000000-0000-4000-8000-000000000001 and so on.
function Get-TestUserId { param([int] $Number) '00000000-0000-4000-8000-{0:d12}' -f $Number }
function Get-TestGroupId { param([int] $Number) '00000000-0000-4000-9000-{0:d12}' -f $Number }
function Get-TestDefinitionId { param([int] $Number) 'def-01JA00000000000000000000{0:d2}' -f $Number }

function Get-TestUser {
    param([int] $Number, [string] $Department = 'Sales', [bool] $Enabled = $true, [string] $UserType = 'Member')
    @{
        id                = Get-TestUserId $Number
        userPrincipalName = "user$Number@contoso.org"
        displayName       = "User $Number"
        accountEnabled    = $Enabled
        userType          = $UserType
        department        = $Department
    }
}

# An in-memory tenant behind the Custom directory kind. $tenant.Groups[id] holds DisplayName,
# GroupTypes, IsDynamic, OnPremisesSynced, IsAssignableToRole, Members (HashSet of IDs), Marker.
function Get-TestTenant {
    # The Custom directory interface fixes the parameter names; the fake doesn't need all of them.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Interface parameters of the Custom directory.')]
    param([object[]] $Users = @())
    $tenant = @{
        Users      = [System.Collections.Generic.List[object]]::new()
        Groups     = @{}
        Recipients = @{}
        FailAdd    = [System.Collections.Generic.HashSet[string]]::new()
        Calls      = [System.Collections.Generic.List[string]]::new()
        NextGroup  = 900
        Throttle   = $false
    }
    foreach ($user in $Users) { $tenant.Users.Add($user) }
    $toGroup = {
        param($id)
        $g = $tenant.Groups[$id]
        $kind = if ($g['Kind']) { $g.Kind } elseif (@($g.GroupTypes) -contains 'Unified') { 'Microsoft365' } else { 'Security' }
        [pscustomobject]@{
            Id = $id; DisplayName = $g.DisplayName; OnPremisesSynced = [bool]$g.OnPremisesSynced; IsAssignableToRole = [bool]$g['IsAssignableToRole']
            IsDynamic = [bool]$g.IsDynamic; MembershipRule = $g['MembershipRule']; GroupTypes = [string[]]@($g.GroupTypes); Identity = "guid-$id"
            Mail = [string]$g['Mail']; GroupType = $kind
        }
    }.GetNewClosure()
    $tenant.Directory = @{
        Kind              = 'Custom'
        Recipients        = $null
        GetUsers          = {
            param($Select, $ExpandManager)
            if ($tenant.Throttle) {
                $exception = [System.Net.Http.HttpRequestException]::new('Too many requests')
                $exception.Data['StatusCode'] = 429
                $exception.Data['RetryAfter'] = 7
                throw $exception
            }
            $tenant.Calls.Add('GetUsers'); [object[]]@($tenant.Users | ForEach-Object { $_.Clone() })
        }.GetNewClosure()
        GetGroup          = { param($GroupId) if ($tenant.Groups.ContainsKey($GroupId)) { & $toGroup $GroupId } else { $null } }.GetNewClosure()
        GetMembers        = {
            param($Group)
            $userIds = @($tenant.Users | ForEach-Object { $_.id })
            [object[]]@($tenant.Groups[$Group.Id].Members | ForEach-Object { [pscustomobject]@{ Id = $_; IsUser = $userIds -contains $_ } })
        }.GetNewClosure()
        GetUserMemberIds  = {
            param($GroupId, $Transitive)
            if (-not $tenant.Groups.ContainsKey($GroupId)) { return [pscustomobject]@{ Found = $false; UserIds = @() } }
            [pscustomobject]@{ Found = $true; UserIds = [string[]]@($tenant.Groups[$GroupId].Members) }
        }.GetNewClosure()
        AddMember         = {
            param($Group, $UserId)
            if ($tenant.FailAdd.Contains($UserId)) { throw 'Insufficient privileges to complete the operation.' }
            $tenant.Calls.Add("Add $UserId"); [void]$tenant.Groups[$Group.Id].Members.Add($UserId)
        }.GetNewClosure()
        RemoveMember      = { param($Group, $UserId) $tenant.Calls.Add("Remove $UserId"); [void]$tenant.Groups[$Group.Id].Members.Remove($UserId) }.GetNewClosure()
        CreateGroup       = {
            param($GroupType, $DisplayName, $MailNickname)
            $tenant.NextGroup++
            $id = '00000000-0000-4000-9000-{0:d12}' -f $tenant.NextGroup
            $types = if ($GroupType -eq 'Microsoft365') { @('Unified') } else { @() }
            $tenant.Groups[$id] = @{ DisplayName = $DisplayName; GroupTypes = $types; MailNickname = $MailNickname; Members = [System.Collections.Generic.HashSet[string]]::new() }
            $tenant.Calls.Add("Create $DisplayName")
            & $toGroup $id
        }.GetNewClosure()
        RenameGroup       = { param($Group, $DisplayName) $tenant.Calls.Add("Rename $DisplayName"); $tenant.Groups[$Group.Id].DisplayName = $DisplayName }.GetNewClosure()
        ConvertToAssigned = {
            param($Group)
            $tenant.Calls.Add('Convert'); $g = $tenant.Groups[$Group.Id]; $g.IsDynamic = $false
            $g.GroupTypes = @($g.GroupTypes | Where-Object { $_ -ne 'DynamicMembership' })
        }.GetNewClosure()
        SetMarker         = { param($Group, $DefinitionId) $tenant.Calls.Add("Marker $DefinitionId"); $tenant.Groups[$Group.Id].Marker = $DefinitionId }.GetNewClosure()
        GetObjectsById    = {
            param($Ids)
            if ($tenant.Throttle) { throw 'throttled' }
            [object[]]@(foreach ($id in $Ids) {
                    $user = $tenant.Users | Where-Object { $_.id -eq $id } | Select-Object -First 1
                    if ($user) { @{ id = $user.id; displayName = $user.displayName; userPrincipalName = $user.userPrincipalName; '@odata.type' = '#microsoft.graph.user' } }
                    elseif ($tenant.Groups.ContainsKey($id)) { @{ id = $id; displayName = $tenant.Groups[$id].DisplayName; '@odata.type' = '#microsoft.graph.group' } }
                })
        }.GetNewClosure()
        SearchUsers       = {
            param($Search)
            [object[]]@($tenant.Users | Where-Object { $_.displayName -like "$Search*" -or $_.userPrincipalName -like "$Search*" } | ForEach-Object { $_.Clone() })
        }.GetNewClosure()
        SearchGroups      = {
            param($Search)
            [object[]]@($tenant.Groups.Keys | Where-Object { $tenant.Groups[$_].DisplayName -like "$Search*" } | Sort-Object | ForEach-Object {
                    $g = $tenant.Groups[$_]
                    $kind = if ($g['Kind']) { $g.Kind } elseif (@($g.GroupTypes) -contains 'Unified') { 'Microsoft365' } else { 'Security' }
                    @{
                        id = $_; displayName = $g.DisplayName; mail = $g['Mail']; groupTypes = @($g.GroupTypes)
                        mailEnabled = $kind -in @('Microsoft365', 'MailEnabledSecurity', 'Distribution'); securityEnabled = $kind -in @('Security', 'MailEnabledSecurity')
                        onPremisesSyncEnabled = [bool]$g.OnPremisesSynced; isAssignableToRole = [bool]$g['IsAssignableToRole']; membershipRule = $g['MembershipRule']
                    }
                })
        }.GetNewClosure()
        GetRecipients     = { [object[]]@($tenant.Recipients.Keys | ForEach-Object { [pscustomobject]@{ ExternalDirectoryObjectId = $_; Guid = $tenant.Recipients[$_] } }) }.GetNewClosure()
    }
    $tenant
}

function Add-TestGroup {
    param(
        [hashtable] $Tenant, [string] $Id, [string] $DisplayName = 'Group', [string[]] $Members = @(), [string[]] $GroupTypes = @(),
        [bool] $IsDynamic = $false, [bool] $OnPremisesSynced = $false, [string] $Kind, [bool] $IsAssignableToRole = $false, [string] $MembershipRule
    )
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($member in $Members) { [void]$set.Add($member) }
    $Tenant.Groups[$Id] = @{
        DisplayName = $DisplayName; GroupTypes = $GroupTypes; IsDynamic = $IsDynamic; OnPremisesSynced = $OnPremisesSynced; Members = $set
        Kind = $Kind; IsAssignableToRole = $IsAssignableToRole; MembershipRule = $MembershipRule
    }
}

function Get-TestSettingDocument {
    param([hashtable] $Change = @{})
    $settings = [ordered]@{
        id = 'settings'; pk = 'settings'; type = 'settings'; schemaVersion = 1
        paused = $false; pausedAt = $null; pausedBy = $null; verboseLogging = $false
        changeLimitPercent = 50; changeLimitMinChanges = 10; newGroupsDryRun = $false; nestedMembers = $true
        frequencyOptions = @(3, 15, 60)
        naming = [ordered]@{ prefix = [ordered]@{ enabled = $false; text = 'DG-' }; suffix = [ordered]@{ enabled = $false; text = '' } }
        marker = [ordered]@{ enabled = $false; exchangeCustomAttribute = 10 }
        auditRetentionDays = 60; updatedAt = $null; updatedBy = $null
    }
    foreach ($key in $Change.Keys) { $settings[$key] = $Change[$key] }
    $settings
}

function Get-TestDefinition {
    param(
        [int] $Number = 1,
        [string] $Rule = 'user.department -eq "Sales"',
        [string] $GroupType = 'Security',
        [hashtable] $Target = $null,
        [hashtable] $Change = @{}
    )
    $id = Get-TestDefinitionId $Number
    if (-not $Target) { $Target = [ordered]@{ mode = 'existing'; groupId = (Get-TestGroupId $Number) } }
    $definition = [ordered]@{
        id = $id; pk = $id; type = 'definition'; schemaVersion = 1
        name = "Definition $Number"; groupType = $GroupType; target = $Target; rule = $Rule
        includeUserIds = @(); excludeUserIds = @(); includeDisabled = $false; includeGuests = $false
        frequencyMinutes = 3; enabled = $true; dryRun = $false; changeLimitPercent = $null; allowEmpty = $false
        compareGroupId = $null; syncRequest = $null; approval = $null
        createdAt = '2026-10-01T08:00:00Z'; createdBy = 'admin@contoso.org'; updatedAt = '2026-10-01T08:00:00Z'; updatedBy = 'admin@contoso.org'
    }
    foreach ($key in $Change.Keys) { $definition[$key] = $Change[$key] }
    $definition
}

# A status document as a previous run would have left it, so the definition is past its first run.
function Get-TestStatus {
    param([int] $Number = 1, [string] $LastSyncUtc = '2026-10-12T07:00:00.000Z', [hashtable] $Change = @{})
    $id = Get-TestDefinitionId $Number
    $status = [ordered]@{
        id = "status-$id"; pk = $id; type = 'status'; schemaVersion = 1; groupId = $null
        lastSyncUtc = $LastSyncUtc; lastResult = 'OK'; dryRunReason = $null; memberCount = 0; added = 0; removed = 0; skipped = 0
        excluded = [ordered]@{ disabled = 0; guests = 0 }; warnings = @(); lastError = $null; lastRunId = $null
        handledSyncRequestAt = $null; pendingApproval = $null; usedApprovalHash = $null; lastWrittenMembersHash = $null; compare = $null
    }
    foreach ($key in $Change.Keys) { $status[$key] = $Change[$key] }
    $status
}

function Get-TestStore {
    param([System.Collections.IDictionary] $Settings = (Get-TestSettingDocument), [object[]] $Definitions = @(), [object[]] $Statuses = @())
    $store = InModuleScope DgEngine { New-DgMemoryStore }
    InModuleScope DgEngine -Parameters @{ S = $store; Settings = $Settings; Definitions = $Definitions; Statuses = $Statuses } {
        [void](Set-DgStoreItem -Store $S -Container config -Document $Settings)
        foreach ($definition in $Definitions) { [void](Set-DgStoreItem -Store $S -Container config -Document $definition) }
        foreach ($status in $Statuses) { [void](Set-DgStoreItem -Store $S -Container state -Document $status) }
    }
    $store
}

function Get-StoredDocument {
    param([hashtable] $Store, [string] $Container, [string] $Type)
    # Find-DgStoreItem returns its array as one object; keep it that way.
    $items = InModuleScope DgEngine -Parameters @{ S = $Store; C = $Container; T = $Type } { Find-DgStoreItem -Store $S -Container $C -Type $T }
    , [object[]]$items
}

function Write-StoredDocument {
    param([hashtable] $Store, [string] $Container, [System.Collections.IDictionary] $Document)
    InModuleScope DgEngine -Parameters @{ S = $Store; C = $Container; D = $Document } { [void](Set-DgStoreItem -Store $S -Container $C -Document $D) }
}

function Invoke-TestSync {
    param(
        [hashtable] $Store,
        [hashtable] $Tenant,
        [string] $Provider = 'Entra',
        [string] $Mode = 'Scheduled',
        [string] $Now = '2026-10-12T08:00:00Z',
        [string] $AccessMode = 'read-write',
        [string] $JobId = ([guid]::NewGuid().ToString()),
        [string] $DefinitionId,
        [hashtable] $ExchangeTenant
    )
    $call = @{
        Provider = $Provider; Mode = $Mode; Store = $Store; GraphDirectory = $Tenant.Directory; AccessMode = $AccessMode
        JobId = $JobId; Now = [DateTimeOffset]::Parse($Now, [System.Globalization.CultureInfo]::InvariantCulture); TickMinutes = 3
    }
    if ($ExchangeTenant) { $call.ExchangeDirectory = $ExchangeTenant.Directory }
    if ($DefinitionId) { $call.DefinitionId = $DefinitionId }
    Invoke-DgSync @call
}

# Validates every document the store holds against its JSON schema (schemas/cosmos).
# Returns the list of problems; empty when all documents conform.
function Test-StoredDocumentSchema {
    param([hashtable] $Store)
    $schemaDir = Join-Path -Path $script:KitRoot -ChildPath 'schemas/cosmos'
    $common = Get-Content -Raw -Path (Join-Path $schemaDir 'common.schema.json')
    $commonDefs = (ConvertFrom-Json -InputObject ($common -replace '"#/\$defs/', '"#/$defs/common_') -AsHashtable)['$defs']
    $schemas = @{}
    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($container in $Store.Containers.Keys) {
        foreach ($entry in $Store.Containers[$container].Values) {
            $type = (ConvertFrom-Json -InputObject $entry.Json -AsHashtable)['type']
            if (-not $schemas.ContainsKey($type)) {
                $text = Get-Content -Raw -Path (Join-Path $schemaDir "$type.schema.json")
                $schema = ConvertFrom-Json -InputObject ($text -replace '"common\.schema\.json#/\$defs/', '"#/$defs/common_') -AsHashtable
                if (-not $schema.ContainsKey('$defs')) { $schema['$defs'] = @{} }
                foreach ($key in $commonDefs.Keys) { $schema['$defs']["common_$key"] = $commonDefs[$key] }
                $schemas[$type] = ConvertTo-Json -InputObject $schema -Depth 50
            }
            $errors = $null
            $ok = Test-Json -Json $entry.Json -Schema $schemas[$type] -ErrorVariable errors -ErrorAction SilentlyContinue
            if (-not $ok) { $problems.Add("$container/$type`: $(@($errors | ForEach-Object { $_.Exception.Message }) -join '; ') :: $($entry.Json)") }
        }
    }
    , $problems.ToArray()
}
