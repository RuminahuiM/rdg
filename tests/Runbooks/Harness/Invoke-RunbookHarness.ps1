#Requires -Version 7.4
<#
.SYNOPSIS
    Runs a built runbook in a fake Azure Automation sandbox and writes what happened to a JSON file.
.DESCRIPTION
    Started in its own pwsh process by tests/Runbooks/*.Tests.ps1. Replaces, as global functions:
    Get-AutomationVariable, the managed identity endpoint (Invoke-RestMethod), Cosmos DB's REST API
    (Invoke-WebRequest), Microsoft Graph (Connect-MgGraph, Invoke-MgGraphRequest), Exchange Online
    (Connect-ExchangeOnline and the distribution group cmdlets) and Key Vault. Everything the
    runbook does goes through the engine's real code paths for these services.
    The state file holds the scenario on input and the result on output: Output, Warnings, Error,
    Cosmos (documents), Groups, Applications, Calls.
    All data is invented (contoso.org).
#>
# The fakes mirror foreign cmdlet signatures and share state through a global variable on purpose.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Fake services share one global state.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Fakes accept the real cmdlets'' parameters.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Fakes accept the real cmdlets'' parameters.')]
param(
    [Parameter(Mandatory)]
    [string] $Runbook,

    [Parameter(Mandatory)]
    [string] $StatePath,

    [string] $ArgumentsJson = '{}'
)

$ErrorActionPreference = 'Stop'
$global:Fake = Get-Content -Raw -Path $StatePath | ConvertFrom-Json -AsHashtable
foreach ($key in @('Cosmos', 'Groups', 'Applications', 'Recipients', 'Variables', 'KeyVault')) {
    if (-not $global:Fake.ContainsKey($key) -or $null -eq $global:Fake[$key]) { $global:Fake[$key] = @{} }
}
foreach ($key in @('Users')) {
    if (-not $global:Fake.ContainsKey($key) -or $null -eq $global:Fake[$key]) { $global:Fake[$key] = @() }
}
$global:Fake.Calls = [System.Collections.Generic.List[string]]::new()
$global:Fake.Version = 100
$env:IDENTITY_ENDPOINT = 'http://127.0.0.1:42356/msi/token'
$env:IDENTITY_HEADER = 'fake-identity-header'

function global:New-FakeHttpError {
    param([int] $Status, [string] $Message)
    $exception = [System.Net.Http.HttpRequestException]::new("Response status code does not indicate success: $Status. $Message")
    $exception.Data['StatusCode'] = $Status
    $exception
}

# --- Azure Automation
function global:Get-AutomationVariable {
    param([Parameter(Mandatory)] [string] $Name)
    if (-not $global:Fake.Variables.ContainsKey($Name)) { throw "Variable '$Name' not found" }
    $global:Fake.Variables[$Name]
}

# --- Managed identity endpoint and Key Vault
function global:Invoke-RestMethod {
    param([string] $Method = 'GET', [string] $Uri, [hashtable] $Headers)
    if ($Uri.StartsWith($env:IDENTITY_ENDPOINT)) {
        if ($Headers['X-IDENTITY-HEADER'] -ne $env:IDENTITY_HEADER) { throw 'identity header missing' }
        $query = [System.Web.HttpUtility]::ParseQueryString(([uri]$Uri).Query)
        $global:Fake.Calls.Add("token $($query['resource']) $($query['client_id'])")
        return [pscustomobject]@{ access_token = "token-for-$($query['client_id'])"; expires_on = [string]([DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()) }
    }
    if ($Uri -match '^https://[^/]+\.vault\.azure\.net/certificates/([^?/]+)') {
        $global:Fake.Calls.Add("keyvault GET $($Matches[1])")
        if ($Headers['Authorization'] -notlike 'Bearer token-for-*') { throw 'no bearer token' }
        $certificate = $global:Fake.KeyVault[$Matches[1]]
        if (-not $certificate) { throw (New-FakeHttpError 404 'CertificateNotFound') }
        return [pscustomobject]@{ id = $Uri; cer = $certificate }
    }
    throw "unexpected Invoke-RestMethod $Method $Uri"
}

# --- Cosmos DB REST API
function global:Invoke-WebRequest {
    param([string] $Method, [string] $Uri, [hashtable] $Headers, [string] $Body, [switch] $SkipHttpErrorCheck, [switch] $SkipHeaderValidation)
    $reply = { param($status, $content, $headers) [pscustomobject]@{ StatusCode = $status; Content = $content; Headers = $(if ($headers) { $headers } else { @{} }) } }
    if ($Headers['Authorization'] -notlike 'type%3Daad%26ver%3D1.0%26sig%3Dtoken-for-*') { return & $reply 401 '{"code":"Unauthorized"}' }
    if ($Uri -notmatch '^https://[^/]+/dbs/([^/]+)/colls/([^/]+)/docs(?:/([^/?]+))?$') { return & $reply 400 '{"code":"BadRequest"}' }
    $container = $Matches[2]
    $id = if ($Matches[3]) { [System.Uri]::UnescapeDataString($Matches[3]) } else { $null }
    if (-not $global:Fake.Cosmos.ContainsKey($container)) { $global:Fake.Cosmos[$container] = @{} }
    $documents = $global:Fake.Cosmos[$container]
    $pk = if ($Headers['x-ms-documentdb-partitionkey']) { ($Headers['x-ms-documentdb-partitionkey'] | ConvertFrom-Json -NoEnumerate)[0] } else { $null }
    $global:Fake.Calls.Add("cosmos $Method $container $id")
    $save = {
        param($document)
        $global:Fake.Version++
        $document['_etag'] = "`"$($global:Fake.Version)`""
        $documents["$($document['pk'])|$($document['id'])"] = $document
    }
    switch ($Method) {
        'GET' {
            $document = $documents["$pk|$id"]
            if (-not $document) { return & $reply 404 '{"code":"NotFound"}' }
            return & $reply 200 ($document | ConvertTo-Json -Depth 30 -Compress)
        }
        'POST' {
            if ($Headers['x-ms-documentdb-isquery'] -eq 'True') {
                $query = ConvertFrom-Json $Body
                $type = $query.parameters[0].value
                $found = @($documents.Values | Where-Object { $_['type'] -eq $type })
                return & $reply 200 (@{ Documents = $found; _count = $found.Count } | ConvertTo-Json -Depth 30 -Compress)
            }
            $document = ConvertFrom-Json $Body -AsHashtable
            if ($document['pk'] -ne $pk) { return & $reply 400 '{"code":"BadRequest","message":"partition key mismatch"}' }
            $exists = $documents.ContainsKey("$pk|$($document['id'])")
            if ($exists -and $Headers['x-ms-documentdb-is-upsert'] -ne 'True') { return & $reply 409 '{"code":"Conflict"}' }
            & $save $document
            return & $reply $(if ($exists) { 200 } else { 201 }) '{}'
        }
        'PUT' {
            $existing = $documents["$pk|$id"]
            if (-not $existing) { return & $reply 404 '{"code":"NotFound"}' }
            if ($Headers['If-Match'] -and $Headers['If-Match'] -ne $existing['_etag']) { return & $reply 412 '{"code":"PreconditionFailed"}' }
            & $save (ConvertFrom-Json $Body -AsHashtable)
            return & $reply 200 '{}'
        }
        'DELETE' {
            $existing = $documents["$pk|$id"]
            if (-not $existing) { return & $reply 404 '{"code":"NotFound"}' }
            if ($Headers['If-Match'] -and $Headers['If-Match'] -ne $existing['_etag']) { return & $reply 412 '{"code":"PreconditionFailed"}' }
            $documents.Remove("$pk|$id")
            return & $reply 204 ''
        }
    }
    & $reply 405 '{}'
}

# --- Microsoft Graph
function global:Connect-MgGraph {
    [CmdletBinding()]
    param([switch] $Identity, [string] $ClientId, [switch] $NoWelcome)
    if (-not $Identity -or -not $ClientId) { throw 'expected -Identity -ClientId' }
    $global:Fake.Calls.Add("Connect-MgGraph $ClientId")
}

function global:Invoke-MgGraphRequest {
    [CmdletBinding()]
    param([string] $Method, [string] $Uri, $Body, [string] $ContentType, [string] $OutputType)
    $path = $Uri -replace '^https://graph\.microsoft\.com/v1\.0', ''
    $data = if ($Body) { ConvertFrom-Json $Body -AsHashtable } else { $null }
    $global:Fake.Calls.Add("graph $Method $path")
    $userIds = @($global:Fake.Users | ForEach-Object { $_['id'] })
    $group = {
        param($id)
        if (-not $global:Fake.Groups.ContainsKey($id)) { throw (New-FakeHttpError 404 'Request_ResourceNotFound') }
        $global:Fake.Groups[$id]
    }
    switch -Regex ($path) {
        '^/users\?' {
            return @{ value = @($global:Fake.Users) }
        }
        '^/groups/([^/?]+)\?' {
            $g = & $group $Matches[1]
            return @{ id = $Matches[1]; displayName = $g['displayName']; groupTypes = @($g['groupTypes']); onPremisesSyncEnabled = $g['onPremisesSyncEnabled']; isAssignableToRole = $false; membershipRule = $null }
        }
        '^/groups/([^/?]+)/(members|transitiveMembers)/microsoft\.graph\.user\?' {
            $g = & $group $Matches[1]
            return @{ value = @($g['members'] | Where-Object { $userIds -contains $_ } | ForEach-Object { @{ id = $_ } }) }
        }
        '^/groups/([^/?]+)/members\?' {
            $g = & $group $Matches[1]
            return @{ value = @($g['members'] | ForEach-Object { @{ id = $_; '@odata.type' = $(if ($userIds -contains $_) { '#microsoft.graph.user' } else { '#microsoft.graph.group' }) } }) }
        }
        '^/groups/([^/?]+)$' {
            $g = & $group $Matches[1]
            if ($Method -ne 'PATCH') { break }
            foreach ($ref in @($data['members@odata.bind'])) {
                if ($ref) { $g['members'] = @($g['members']) + @(($ref -split '/')[-1]) }
            }
            if ($data.ContainsKey('displayName')) { $g['displayName'] = $data['displayName'] }
            return $null
        }
        '^/\$batch$' {
            $responses = foreach ($request in $data['requests']) {
                $null = $request['url'] -match '^/groups/([^/]+)/members/([^/]+)/\$ref$'
                $g = $global:Fake.Groups[$Matches[1]]
                $member = $Matches[2]
                if ($g -and @($g['members']) -contains $member) {
                    $g['members'] = @($g['members'] | Where-Object { $_ -ne $member })
                    @{ id = $request['id']; status = 204 }
                } else {
                    @{ id = $request['id']; status = 404 }
                }
            }
            return @{ responses = @($responses) }
        }
        "^/applications\(appId='([^']+)'\)\?" {
            $app = $global:Fake.Applications[$Matches[1]]
            if (-not $app) { throw (New-FakeHttpError 404 'Request_ResourceNotFound') }
            return @{ id = $app['id']; keyCredentials = @($app['keyCredentials']) }
        }
        '^/applications/([^/?]+)$' {
            $objectId = $Matches[1]
            $app = $global:Fake.Applications.Values | Where-Object { $_['id'] -eq $objectId } | Select-Object -First 1
            if (-not $app) { throw (New-FakeHttpError 404 'Request_ResourceNotFound') }
            $app['keyCredentials'] = @($data['keyCredentials'])
            return $null
        }
    }
    throw (New-FakeHttpError 400 "unexpected Graph call $Method $path")
}

# --- Exchange Online
function global:Connect-ExchangeOnline {
    [CmdletBinding()]
    param([switch] $ManagedIdentity, [string] $Organization, [string] $ManagedIdentityAccountId, [string[]] $CommandName, [switch] $ShowBanner)
    if (-not $ManagedIdentity -or -not $Organization -or -not $ManagedIdentityAccountId) { throw 'expected managed identity parameters' }
    $global:Fake.Calls.Add("Connect-ExchangeOnline $Organization $ManagedIdentityAccountId")
}

function global:Get-FakeExchangeGroup {
    param([string] $Id)
    $g = $global:Fake.Groups[$Id]
    [pscustomobject]@{ ExternalDirectoryObjectId = $Id; DisplayName = $g['displayName']; IsDirSynced = [bool]$g['onPremisesSyncEnabled']; Guid = "guid-$Id" }
}

function global:Get-DistributionGroup {
    [CmdletBinding()]
    param([string] $Filter, [string] $Identity, $ResultSize)
    if ($Filter -match "ExternalDirectoryObjectId -eq '([^']+)'") {
        if ($global:Fake.Groups.ContainsKey($Matches[1])) { return Get-FakeExchangeGroup -Id $Matches[1] }
        return
    }
    $id = $Identity -replace '^guid-', ''
    Get-FakeExchangeGroup -Id $id
}

function global:Get-DistributionGroupMember {
    [CmdletBinding()]
    param([string] $Identity, $ResultSize)
    $g = $global:Fake.Groups[($Identity -replace '^guid-', '')]
    foreach ($member in @($g['members'])) {
        if ($member) { [pscustomobject]@{ ExternalDirectoryObjectId = $member; RecipientType = 'UserMailbox' } }
    }
}

function global:Add-DistributionGroupMember {
    [CmdletBinding()]
    param([string] $Identity, [string] $Member, [switch] $BypassSecurityGroupManagerCheck, [switch] $Confirm)
    $g = $global:Fake.Groups[($Identity -replace '^guid-', '')]
    $userId = ($global:Fake.Recipients.GetEnumerator() | Where-Object { $_.Value -eq $Member } | Select-Object -First 1).Key
    if (-not $userId) { throw "Couldn't find object ""$Member""." }
    $g['members'] = @($g['members']) + @($userId)
    $global:Fake.Calls.Add("exchange add $userId")
}

function global:Remove-DistributionGroupMember {
    [CmdletBinding()]
    param([string] $Identity, [string] $Member, [switch] $BypassSecurityGroupManagerCheck, [switch] $Confirm)
    $g = $global:Fake.Groups[($Identity -replace '^guid-', '')]
    $userId = ($global:Fake.Recipients.GetEnumerator() | Where-Object { $_.Value -eq $Member } | Select-Object -First 1).Key
    if (-not $userId) { $userId = $Member }
    $g['members'] = @($g['members'] | Where-Object { $_ -ne $userId })
    $global:Fake.Calls.Add("exchange remove $userId")
}

function global:Get-EXORecipient {
    [CmdletBinding()]
    param($ResultSize, [string[]] $RecipientTypeDetails, [string[]] $Properties)
    foreach ($entry in $global:Fake.Recipients.GetEnumerator()) {
        [pscustomobject]@{ ExternalDirectoryObjectId = $entry.Key; Guid = $entry.Value }
    }
}

# --- Run the runbook
$arguments = ConvertFrom-Json $ArgumentsJson -AsHashtable
$output = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$failure = $null
try {
    & $Runbook @arguments 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) { $warnings.Add($_.Message) } else { $output.Add([string]$_) }
    }
} catch {
    $failure = $_.Exception.Message
}

$cosmos = @{}
foreach ($container in $global:Fake.Cosmos.Keys) { $cosmos[$container] = @($global:Fake.Cosmos[$container].Values) }
$result = [ordered]@{
    Output       = $output.ToArray()
    Warnings     = $warnings.ToArray()
    Error        = $failure
    Cosmos       = $cosmos
    Groups       = $global:Fake.Groups
    Applications = $global:Fake.Applications
    Calls        = $global:Fake.Calls.ToArray()
}
$result | ConvertTo-Json -Depth 30 | Set-Content -Path $StatePath -Encoding utf8NoBOM
