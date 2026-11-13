#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.20.0' }
<#
.SYNOPSIS
    Creates invented, cloud-only test users (and a few guests) in a TEST tenant.
.DESCRIPTION
    For the test installation described in the Infrastructure design ("Testing before production"):
    users RDG Test 01..NN (rdgtestNN@<domain>) with department, job title, city, country,
    employee ID and extensionAttribute1-3 set, extensionAttribute15 = rdg-test, every sixth one
    disabled (with the default 30 users each of the 5 departments has 5 active users, as
    New-RdgTestGroups.ps1 needs); and guests rdgguestNN@example.com, invited without an email. Passwords are random
    and not shown; nobody signs in as these users.
    Idempotent: existing test users are brought in line with the data (department, enabled
    and so on), nothing else is touched. -Remove deletes them again (they stay in Deleted users
    for 30 days).
    Refuses tenants with more than 100 users unless -Force, so it isn't run against a
    production tenant by mistake.
.EXAMPLE
    ./bootstrap/New-RdgTestUsers.ps1 -TenantDomain contoso.onmicrosoft.com -Count 30 -GuestCount 3
.EXAMPLE
    ./bootstrap/New-RdgTestUsers.ps1 -TenantDomain contoso.onmicrosoft.com -Remove
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')]
    [string] $TenantDomain,

    [ValidateRange(1, 50)]
    [int] $Count = 30,

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
$updated = 0
foreach ($user in $users) {
    $properties = @{
        accountEnabled = $user.AccountEnabled
        department     = $user.Department
        jobTitle       = $user.JobTitle
        city           = $user.City
        country        = $user.Country
        usageLocation  = $user.UsageLocation
        employeeId     = $user.EmployeeId
    }
    $filter = [uri]::EscapeDataString("userPrincipalName eq '$($user.UserPrincipalName)'")
    $existing = @((Invoke-RdgGraphRequest -Method GET -Uri "/users?`$filter=$filter&`$select=id").value)
    if ($existing.Count -gt 0) {
        # Bring an existing test user in line with the data, e.g. after the data changed.
        if (-not $PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Update test user')) { continue }
        $properties.onPremisesExtensionAttributes = $user.ExtensionAttributes
        [void](Invoke-RdgGraphRequest -Method PATCH -Uri "/users/$($existing[0].id)" -Body $properties)
        $updated++
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($user.UserPrincipalName, 'Create test user')) { continue }
    $properties.displayName = $user.DisplayName
    $properties.mailNickname = $user.MailNickname
    $properties.userPrincipalName = $user.UserPrincipalName
    $properties.passwordProfile = @{ forceChangePasswordNextSignIn = $true; password = (Get-RandomPassword) }
    $new = Invoke-RdgGraphRequest -Method POST -Uri '/users' -Body $properties
    # Cloud-only users: the extension attributes can be written after creation.
    [void](Invoke-RdgGraphRequest -Method PATCH -Uri "/users/$($new.id)" -Body @{ onPremisesExtensionAttributes = $user.ExtensionAttributes })
    $created++
}

$invited = 0
$failed = 0
foreach ($guest in $guests) {
    $filter = [uri]::EscapeDataString("mail eq '$($guest.Email)'")
    $existing = @((Invoke-RdgGraphRequest -Method GET -Uri "/users?`$filter=$filter&`$select=id").value)
    if ($existing.Count -gt 0) { continue }
    if (-not $PSCmdlet.ShouldProcess($guest.Email, 'Invite test guest (no email is sent)')) { continue }
    # Guests are optional test data: a refused invitation (new tenants can be blocked from
    # inviting for a while) is reported, the users above stay.
    try {
        [void](Invoke-RdgGraphRequest -Method POST -Uri '/invitations' -Body @{
                invitedUserEmailAddress = $guest.Email
                invitedUserDisplayName  = $guest.DisplayName
                inviteRedirectUrl       = 'https://myapps.microsoft.com'
                sendInvitationMessage   = $false
            })
        $invited++
    } catch {
        $failed++
        Write-Warning -Message "Could not invite $($guest.Email): $($_.Exception.Message)"
    }
}

$summary = "Created $created and updated $updated test user(s), invited $invited guest(s) in $TenantDomain."
if ($failed -gt 0) { $summary += " $failed guest invitation(s) failed, see the warnings above; run the script again later." }
Write-Information -MessageData $summary -InformationAction Continue
