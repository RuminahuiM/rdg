#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.20.0' }
<#
.SYNOPSIS
    Creates invented, cloud-only test users (and a few guests) in a TEST tenant.
.DESCRIPTION
    For the test installation described in the Infrastructure design ("Testing before HEKS"):
    users RDG Test 01..NN (rdgtestNN@<domain>) with department, job title, city, country,
    employee ID and extensionAttribute1-3 set, extensionAttribute15 = rdg-test, every fifth one
    disabled; and guests rdgguestNN@example.com, invited without an email. Passwords are random
    and not shown; nobody signs in as these users.
    Idempotent: existing users are left as they are. -Remove deletes them again (they stay in
    Deleted users for 30 days).
    Refuses tenants with more than 100 users unless -Force, so it isn't run against a
    production tenant by mistake.
.EXAMPLE
    ./bootstrap/New-RdgTestUsers.ps1 -TenantDomain contoso.onmicrosoft.com -Count 15 -GuestCount 3
.EXAMPLE
    ./bootstrap/New-RdgTestUsers.ps1 -TenantDomain contoso.onmicrosoft.com -Remove
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')]
    [string] $TenantDomain,

    [ValidateRange(1, 50)]
    [int] $Count = 15,

    [ValidateRange(0, 10)]
    [int] $GuestCount = 3,

    [switch] $Remove,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RdgBootstrap.psm1') -Force

function Get-RandomPassword {
    # 24 random characters; never printed or stored.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%+-=?'
    $chars = foreach ($i in 1..24) { $alphabet[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($alphabet.Length)] }
    'Rdg1!' + (-join $chars)
}

Connect-MgGraph -NoWelcome -Scopes @('User.ReadWrite.All', 'User.Invite.All')
$organization = Invoke-RdgGraphRequest -Method GET -Uri '/organization?$select=id,displayName,verifiedDomains'
$domains = @($organization.value | ForEach-Object { @($_.verifiedDomains) } | ForEach-Object { [string]$_.name })
if ($domains -notcontains $TenantDomain) { throw "$TenantDomain is not a verified domain of the signed-in tenant ($($domains -join ', '))." }

$probe = Invoke-RdgGraphRequest -Method GET -Uri '/users?$select=id&$top=101'
if (@($probe.value).Count -gt 100 -and -not $Force) {
    throw 'This tenant has more than 100 users; it doesn''t look like a test tenant. Use -Force if you are sure.'
}

$users = @(Get-RdgTestUserData -Count $Count -Domain $TenantDomain)
$guests = @(for ($i = 1; $i -le $GuestCount; $i++) {
        $n = '{0:d2}' -f $i
        [pscustomobject]@{ DisplayName = "RDG Guest $n"; Email = "rdgguest$n@example.com" }
    })

if ($Remove) {
    $found = @(Invoke-RdgGraphRequest -Method GET -All -Uri ("/users?`$filter=" + [uri]::EscapeDataString("startswith(userPrincipalName,'rdgtest')") + "&`$select=id,userPrincipalName"))
    $found += @(Invoke-RdgGraphRequest -Method GET -All -Uri ("/users?`$filter=" + [uri]::EscapeDataString("startswith(mail,'rdgguest') and userType eq 'Guest'") + "&`$select=id,userPrincipalName"))
    foreach ($user in $found) {
        if ($PSCmdlet.ShouldProcess([string]$user.userPrincipalName, 'Delete test user')) {
            [void](Invoke-RdgGraphRequest -Method DELETE -Uri "/users/$($user.id)")
        }
    }
    Write-Information -MessageData "Deleted $(@($found).Count) test user(s)." -InformationAction Continue
    return
}

$created = 0
foreach ($user in $users) {
    $filter = [uri]::EscapeDataString("userPrincipalName eq '$($user.UserPrincipalName)'")
    $existing = @((Invoke-RdgGraphRequest -Method GET -Uri "/users?`$filter=$filter&`$select=id").value)
    if ($existing.Count -gt 0) { continue }
    if (-not $PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Create test user')) { continue }
    $new = Invoke-RdgGraphRequest -Method POST -Uri '/users' -Body @{
        accountEnabled    = $user.AccountEnabled
        displayName       = $user.DisplayName
        mailNickname      = $user.MailNickname
        userPrincipalName = $user.UserPrincipalName
        passwordProfile   = @{ forceChangePasswordNextSignIn = $true; password = (Get-RandomPassword) }
        department        = $user.Department
        jobTitle          = $user.JobTitle
        city              = $user.City
        country           = $user.Country
        usageLocation     = $user.UsageLocation
        employeeId        = $user.EmployeeId
    }
    # Cloud-only users: the extension attributes can be written after creation.
    [void](Invoke-RdgGraphRequest -Method PATCH -Uri "/users/$($new.id)" -Body @{ onPremisesExtensionAttributes = $user.ExtensionAttributes })
    $created++
}

$invited = 0
foreach ($guest in $guests) {
    $filter = [uri]::EscapeDataString("mail eq '$($guest.Email)'")
    $existing = @((Invoke-RdgGraphRequest -Method GET -Uri "/users?`$filter=$filter&`$select=id").value)
    if ($existing.Count -gt 0) { continue }
    if (-not $PSCmdlet.ShouldProcess($guest.Email, 'Invite test guest (no email is sent)')) { continue }
    [void](Invoke-RdgGraphRequest -Method POST -Uri '/invitations' -Body @{
            invitedUserEmailAddress = $guest.Email
            invitedUserDisplayName  = $guest.DisplayName
            inviteRedirectUrl       = 'https://myapps.microsoft.com'
            sendInvitationMessage   = $false
        })
    $invited++
}

Write-Information -MessageData "Created $created test user(s) and invited $invited guest(s) in $TenantDomain." -InformationAction Continue
