# Building blocks for the API tests: an in-memory store and tenant (from the engine's test kit),
# requests shaped like the Functions host's, and a check of every response against the response
# schema openapi.yaml declares for that operation and status. Dot-source in BeforeAll.

. (Join-Path -Path $PSScriptRoot -ChildPath '../DgEngine/Sync/SyncTestKit.ps1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../src/DgEngine/DgEngine.psd1') -Force -Global
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../src/Api/Modules/DgApi/DgApi.psd1') -Force

$script:OpenApi = Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../src/Api/Modules/DgApi/openapi.json') | ConvertFrom-Json -AsHashtable
$script:ApiDefs = (ConvertTo-Json -InputObject $script:OpenApi.components.schemas -Depth 60 -Compress) -replace '#/components/schemas/', '#/$defs/'
$script:ContractFailures = [System.Collections.Generic.List[string]]::new()

# A fresh API world: tenant (Custom directory), store with settings, and a job starter that records jobs.
function Get-ApiWorld {
    param([object[]] $Users = @(), [string] $AccessMode = 'read-write', [hashtable] $Settings = @{})
    $tenant = Get-TestTenant -Users $Users
    $store = Get-TestStore -Settings (Get-TestSettingDocument -Change $Settings)
    $jobs = [System.Collections.Generic.List[object]]::new()
    $world = @{ Tenant = $tenant; Store = $store; Jobs = $jobs; FailJobs = $false; Clock = [DateTimeOffset]'2026-10-12T08:00:00Z' }
    Set-DgApiContext -Context @{
        Store               = $store
        Graph               = $tenant.Directory
        AccessMode          = $AccessMode
        AutomationAccountId = '/subscriptions/00000000-0000-4000-8000-0000000000aa/resourceGroups/rg-rdg/providers/Microsoft.Automation/automationAccounts/aa-rdg'
        StartJob            = {
            param($Runbook, $Parameters)
            if ($world.FailJobs) { throw 'AuthorizationFailed' }
            $world.Jobs.Add([pscustomobject]@{ Runbook = $Runbook; Parameters = $Parameters })
            '00000000-0000-4000-8000-0000000000b1'
        }.GetNewClosure()
        Now                 = { $world.Clock }.GetNewClosure()
    }
    $world
}

function Get-Principal {
    param([string[]] $Roles = @('admin'), [string] $Upn = 'admin@contoso.org')
    $json = @{ identityProvider = 'aad'; userId = 'u1'; userDetails = $Upn; userRoles = @(@('anonymous', 'authenticated') + $Roles) } | ConvertTo-Json -Compress
    [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
}

# Calls the API like the host would and returns StatusCode, Headers, Body (parsed) and Raw.
# Every response is checked against openapi.yaml; failures are collected in $script:ContractFailures.
function Invoke-Api {
    param(
        [string] $Method = 'GET',
        [string] $Route,
        [hashtable] $Params = @{},
        [hashtable] $Query = @{},
        $Body,
        [string[]] $Roles = @('admin'),
        [string] $Upn = 'admin@contoso.org',
        [switch] $Anonymous,
        [string] $IfMatch,
        [string] $RawBody
    )
    $headers = @{}
    if (-not $Anonymous) { $headers['x-ms-client-principal'] = Get-Principal -Roles $Roles -Upn $Upn }
    if ($IfMatch) { $headers['If-Match'] = $IfMatch }
    $request = @{ Method = $Method; Headers = $headers; Query = $Query; Params = $Params }
    if ($PSBoundParameters.ContainsKey('RawBody')) { $request.RawBody = $RawBody }
    elseif ($null -ne $Body) { $request.RawBody = ConvertTo-Json -InputObject $Body -Depth 30 -Compress }
    $response = Invoke-DgApiFunction -Route $Route -Request $request -InformationAction SilentlyContinue -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    $problem = Test-ApiContract -Route $Route -Method $Method -Response $response
    if ($problem) { $script:ContractFailures.Add($problem) }
    [pscustomobject]@{
        StatusCode = $response.StatusCode
        Headers    = $response.Headers
        Raw        = $response.Body
        Body       = if ($response.Body) { ConvertFrom-Json -InputObject $response.Body -AsHashtable } else { $null }
    }
}

# The status must be declared for the operation, and the body must match its declared schema.
function Test-ApiContract {
    param([string] $Route, [string] $Method, [hashtable] $Response)
    $operation = $script:OpenApi.paths['/' + $Route][$Method.ToLowerInvariant()]
    if (-not $operation) { return "$Method $Route is not in the contract" }
    $declared = $operation.responses[[string]$Response.StatusCode]
    # 500 can happen on any operation; its body is a Problem like every other error.
    if (-not $declared -and $Response.StatusCode -eq 500) { $declared = $script:OpenApi.components.responses['BadRequest'] }
    if (-not $declared) { return "$Method $Route answered $($Response.StatusCode), which the contract doesn't declare" }
    if ($declared.ContainsKey('$ref')) { $declared = $script:OpenApi.components.responses[($declared['$ref'] -split '/')[-1]] }
    if (-not $declared['content']) {
        if ($Response.Body) { return "$Method $Route $($Response.StatusCode) has a body the contract doesn't declare" }
        return $null
    }
    $contentType = @($declared.content.Keys)[0]
    if ($Response.Headers['Content-Type'] -ne $contentType) { return "$Method $Route $($Response.StatusCode): Content-Type $($Response.Headers['Content-Type']), expected $contentType" }
    $schema = (ConvertTo-Json -InputObject $declared.content[$contentType].schema -Depth 60 -Compress) -replace '#/components/schemas/', '#/$defs/'
    $document = '{"$schema":"https://json-schema.org/draft/2020-12/schema","allOf":[' + $schema + '],"$defs":' + $script:ApiDefs + '}'
    $errors = $null
    if (-not (Test-Json -Json $Response.Body -Schema $document -ErrorVariable errors -ErrorAction SilentlyContinue)) {
        return "$Method $Route $($Response.StatusCode) body doesn't match the contract: $(@($errors | ForEach-Object { $_.Exception.Message }) -join '; ') :: $($Response.Body)"
    }
    $null
}

# Creates a definition through the API and returns the response body; fails the test otherwise.
function Add-ApiDefinition {
    param([hashtable] $Body)
    $response = Invoke-Api -Method POST -Route 'definitions' -Body $Body
    if ($response.StatusCode -ne 201) { throw "create failed: $($response.StatusCode) $($response.Raw)" }
    $response.Body
}

function Get-DefinitionInput {
    param([string] $Name = 'Sales', [string] $GroupId = (Get-TestGroupId 1), [string] $Rule = 'user.department -eq "Sales"', [hashtable] $Change = @{}, [string] $Mode = 'existing')
    $body = @{ name = $Name; groupType = 'Security'; target = @{ mode = $Mode; groupId = $GroupId }; rule = $Rule }
    foreach ($key in $Change.Keys) { $body[$key] = $Change[$key] }
    $body
}
