#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.20.0' }
<#
.SYNOPSIS
    Creates the target groups of the read-only test plan (or removes them again).
.DESCRIPTION
    Nine groups named <Prefix>SEC, M365, DL, MESG, Seeded, Child, Parent, Compare and Role, for
    testing an installation against real users without touching any existing group:
      SEC, M365, DL, MESG  empty, one per group type
      Seeded               3 users of -OtherDepartment (users a -Department rule must remove)
      Child                2 users of -Department
      Parent               Child as its only member (nested groups)
      Compare              3 users of -Department and 2 of -OtherDepartment (compareGroupId)
      Role                 empty, role-assignable (Entra ID P1; left out with -SkipRoleAssignable)
    Mail-enabled groups are hidden from the address lists and the M365 group sends no welcome
    mail, so users don't notice them. RDG itself never writes to them in read-only mode; this
    script is run by an admin.
    Always run it with -WhatIf first: it then only reads, and prints every group and member it
    would create. Idempotent: existing groups and memberships are left as they are. -Remove
    deletes the groups for good (the Microsoft 365 group is purged from the recycle bin too).
.EXAMPLE
    ./bootstrap/New-RdgTestGroups.ps1 -TenantId $tenant -Department IT -WhatIf
.EXAMPLE
    ./bootstrap/New-RdgTestGroups.ps1 -TenantId $tenant -Remove -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Create')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string] $TenantId,

    # Department whose users the tests' main rule matches (user.department -eq "<Department>").
    [Parameter(Mandatory, ParameterSetName = 'Create')]
    [string] $Department,

    # Department for users that must NOT match; default: the largest other department.
    [Parameter(ParameterSetName = 'Create')]
    [string] $OtherDepartment,

    [ValidatePattern('^[A-Za-z0-9-]{1,20}$')]
    [string] $Prefix = 'RDG-Test-',

    [switch] $SkipRoleAssignable,

    [switch] $SkipExchange,

    [Parameter(Mandatory, ParameterSetName = 'Remove')]
    [switch] $Remove
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RdgBootstrap.psm1') -Force

$description = 'RDG read-only test group. Safe to delete.'
$scopes = @('Group.ReadWrite.All', 'User.Read.All')
if (-not $SkipRoleAssignable) { $scopes += 'RoleManagement.ReadWrite.Directory' }
Connect-MgGraph -TenantId $TenantId -NoWelcome -Scopes $scopes

function Find-Group {
    param([string] $Name)
    $filter = [uri]::EscapeDataString("displayName eq '$Name'")
    @(Invoke-RdgGraphRequest -Method GET -Uri "/groups?`$filter=$filter&`$select=id,displayName,groupTypes,mailEnabled,securityEnabled" -All) | Select-Object -First 1
}

function Invoke-WithRetry {
    # A new group takes a few seconds to replicate before members can be added.
    param([scriptblock] $Action)
    for ($attempt = 1; ; $attempt++) {
        try { return & $Action } catch {
            if ($attempt -ge 8) { throw }
            Start-Sleep -Seconds 5
        }
    }
}

$kinds = [ordered]@{
    SEC = 'Security'; M365 = 'Microsoft365'; DL = 'Distribution'; MESG = 'MailEnabledSecurity'; Seeded = 'Security'
    Child = 'Security'; Parent = 'Security'; Compare = 'Security'; Role = 'RoleAssignable'
}

$exchangeConnected = $false
function Connect-Exchange {
    if ($script:exchangeConnected) { return }
    Import-Module -Name ExchangeOnlineManagement -MinimumVersion 3.0.0
    Connect-ExchangeOnline -ShowBanner:$false
    $script:exchangeConnected = $true
}

# --- Remove (Parent before Child does not matter: deleting a group drops its memberships)
if ($Remove) {
    try {
        foreach ($key in @($kinds.Keys)) {
            $name = "$Prefix$key"
            $group = Find-Group -Name $name
            if (-not $group) { continue }
            if ($kinds[$key] -in @('Distribution', 'MailEnabledSecurity')) {
                Connect-Exchange
                if ($PSCmdlet.ShouldProcess($name, 'Delete distribution group')) { Remove-DistributionGroup -Identity $name -BypassSecurityGroupManagerCheck -Confirm:$false }
            } elseif ($PSCmdlet.ShouldProcess($name, 'Delete group')) {
                [void](Invoke-RdgGraphRequest -Method DELETE -Uri "/groups/$($group.id)")
                # A deleted Microsoft 365 group stays restorable for 30 days and keeps its mail
                # address; purge it so the test setup can run again.
                if ($kinds[$key] -eq 'Microsoft365') {
                    Invoke-WithRetry { [void](Invoke-RdgGraphRequest -Method DELETE -Uri "/directory/deletedItems/$($group.id)") }
                }
            }
        }
    } finally {
        if ($exchangeConnected) { Disconnect-ExchangeOnline -Confirm:$false }
    }
    return
}

# --- Users (read only)
$users = @(Invoke-RdgGraphRequest -Method GET -Uri '/users?$select=id,userPrincipalName,department,accountEnabled,userType&$top=999' -All |
        Where-Object { $_.accountEnabled -and $_.userType -eq 'Member' })
$match = @($users | Where-Object { $_.department -eq $Department } | Sort-Object -Property userPrincipalName)
if ($match.Count -lt 5) { throw "Department '$Department' has $($match.Count) active member users; the tests need at least 5." }
if (-not $OtherDepartment) {
    $OtherDepartment = ($users | Where-Object { $_.department -and $_.department -ne $Department } |
        Group-Object -Property department | Sort-Object -Property Count -Descending | Select-Object -First 1).Name
}
$other = @($users | Where-Object { $_.department -eq $OtherDepartment } | Sort-Object -Property userPrincipalName)
if ($other.Count -lt 5) { throw "Department '$OtherDepartment' has $($other.Count) active member users; the tests need at least 5." }

$plan = [ordered]@{
    SEC     = @{ Kind = 'Security'; Users = @() }
    M365    = @{ Kind = 'Microsoft365'; Users = @() }
    DL      = @{ Kind = 'Distribution'; Users = @() }
    MESG    = @{ Kind = 'MailEnabledSecurity'; Users = @() }
    Seeded  = @{ Kind = 'Security'; Users = @($other[0..2]) }
    Child   = @{ Kind = 'Security'; Users = @($match[0..1]) }
    Parent  = @{ Kind = 'Security'; Users = @(); Groups = @('Child') }
    Compare = @{ Kind = 'Security'; Users = @($match[2..4]) + @($other[3..4]) }
    Role    = @{ Kind = 'RoleAssignable'; Users = @() }
}
if ($SkipRoleAssignable) { $plan.Remove('Role') }
if ($SkipExchange) { $plan.Remove('DL'); $plan.Remove('MESG') }

Write-Information -InformationAction Continue -MessageData "Department '$Department': $($match.Count) users. Other department '$OtherDepartment': $($other.Count) users."
foreach ($key in $plan.Keys) {
    $entry = $plan[$key]
    $members = @($entry.Users | ForEach-Object { $_.userPrincipalName }) + @($entry['Groups'] | Where-Object { $_ } | ForEach-Object { "$Prefix$_ (group)" })
    Write-Information -InformationAction Continue -MessageData ("  {0,-20} {1,-20} {2}" -f "$Prefix$key", $entry.Kind, ($(if ($members) { $members -join ', ' } else { 'empty' })))
}

try {
    # --- Create
    $ids = @{}
    foreach ($key in $plan.Keys) {
        $name = "$Prefix$key"
        $entry = $plan[$key]
        $group = Find-Group -Name $name
        if ($group) { $ids[$key] = [string]$group.id; continue }
        switch ($entry.Kind) {
            { $_ -in @('Distribution', 'MailEnabledSecurity') } {
                Connect-Exchange
                if ($PSCmdlet.ShouldProcess($name, "Create $($entry.Kind) group (hidden from address lists)")) {
                    $type = if ($entry.Kind -eq 'Distribution') { 'Distribution' } else { 'Security' }
                    [void](New-DistributionGroup -Name $name -Alias $name -Type $type -Notes $description -MemberJoinRestriction Closed -MemberDepartRestriction Closed)
                    Invoke-WithRetry { Set-DistributionGroup -Identity $name -HiddenFromAddressListsEnabled $true -BypassSecurityGroupManagerCheck }
                    $ids[$key] = [string](Invoke-WithRetry { $found = Find-Group -Name $name; if (-not $found) { throw 'not replicated yet' }; $found }).id
                }
            }
            default {
                $body = @{ displayName = $name; mailNickname = $name; description = $description; mailEnabled = $false; securityEnabled = $true; groupTypes = @() }
                if ($entry.Kind -eq 'Microsoft365') {
                    $body.mailEnabled = $true; $body.securityEnabled = $false; $body.groupTypes = @('Unified'); $body.visibility = 'Private'
                    $body.resourceBehaviorOptions = @('WelcomeEmailDisabled', 'HideGroupInOutlook')
                }
                if ($entry.Kind -eq 'RoleAssignable') { $body.isAssignableToRole = $true }
                if ($PSCmdlet.ShouldProcess($name, "Create $($entry.Kind) group")) {
                    $ids[$key] = [string](Invoke-RdgGraphRequest -Method POST -Uri '/groups' -Body $body).id
                }
            }
        }
    }

    # --- Members
    foreach ($key in $plan.Keys) {
        $name = "$Prefix$key"
        $entry = $plan[$key]
        $wanted = @($entry.Users | ForEach-Object { @{ Id = [string]$_.id; Label = [string]$_.userPrincipalName } })
        foreach ($groupKey in @($entry['Groups'] | Where-Object { $_ })) {
            $wanted += @{ Id = $ids[$groupKey]; Label = "$Prefix$groupKey" }
        }
        if (-not $wanted) { continue }
        $current = if ($ids[$key]) { @(Invoke-RdgGraphRequest -Method GET -Uri "/groups/$($ids[$key])/members?`$select=id" -All | ForEach-Object { [string]$_.id }) } else { @() }
        foreach ($member in $wanted) {
            if ($member.Id -and $current -contains $member.Id) { continue }
            if ($PSCmdlet.ShouldProcess($name, "Add member $($member.Label)")) {
                Invoke-WithRetry {
                    [void](Invoke-RdgGraphRequest -Method POST -Uri "/groups/$($ids[$key])/members/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($member.Id)" })
                }
            }
        }
    }

    if ($WhatIfPreference) { return }
    foreach ($key in $plan.Keys) {
        [pscustomobject]@{ Name = "$Prefix$key"; Kind = $plan[$key].Kind; Id = $ids[$key] }
    }
} finally {
    if ($exchangeConnected) { Disconnect-ExchangeOnline -Confirm:$false }
}
