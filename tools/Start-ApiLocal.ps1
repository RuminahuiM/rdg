#Requires -Version 7.4
<#
.SYNOPSIS
    Runs the API locally without Azure: the real function routes and DgApi handlers, an in-memory
    store and an invented tenant (contoso.org), behind a small HTTP listener.
.DESCRIPTION
    For trying the API and for web app development without a tenant. It reads the routes from the
    function.json files, so it serves exactly what the Function App serves, and plays the Static
    Web App's part by adding the x-ms-client-principal header for the chosen role.
    The real host is Azure Functions Core Tools (`func start` in src/Api after
    tools/Build-ApiPackage.ps1 -Local); this script is the no-install alternative.
    Stop with Ctrl+C.
.EXAMPLE
    ./tools/Start-ApiLocal.ps1 -Port 7071 -Role admin
#>
[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int] $Port = 7071,

    [ValidateSet('admin', 'reader', 'none')]
    [string] $Role = 'admin',

    [string] $Upn = 'admin@contoso.org',

    [ValidateSet('read-only', 'read-write')]
    [string] $AccessMode = 'read-write',

    # Stop after this many requests (used by the tests); 0 = run until stopped.
    [int] $MaxRequests = 0
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
. (Join-Path -Path $root -ChildPath 'tests/DgEngine/Sync/SyncTestKit.ps1')
Import-Module -Name (Join-Path -Path $root -ChildPath 'src/DgEngine/DgEngine.psd1') -Global -Force
Import-Module -Name (Join-Path -Path $root -ChildPath 'src/Api/Modules/DgApi/DgApi.psd1') -Force

# Invented tenant: a few users and groups, one definition with a status.
$users = @(1..6 | ForEach-Object { Get-TestUser $_ -Department $(if ($_ % 2) { 'Sales' } else { 'Finance' }) })
$tenant = Get-TestTenant -Users $users
Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 1) -DisplayName 'Sales' -Members @((Get-TestUserId 1))
Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 2) -DisplayName 'Finance'
Add-TestGroup -Tenant $tenant -Id (Get-TestGroupId 3) -DisplayName 'All staff (dynamic)' -IsDynamic $true -GroupTypes @('DynamicMembership') -MembershipRule 'user.accountEnabled -eq true'
$engine = Get-Module -Name DgEngine
$store = & $engine { New-DgMemoryStore }
& $engine {
    param($Store, $Documents)
    foreach ($entry in $Documents) { [void](Set-DgStoreItem -Store $Store -Container $entry.Container -Document $entry.Document) }
} $store @(
    @{ Container = 'config'; Document = (Get-TestSettingDocument) }
    @{ Container = 'config'; Document = (Get-TestDefinition -Change @{ name = 'Sales' }) }
    @{ Container = 'state'; Document = (Get-TestStatus) }
)
Set-DgApiContext -Context @{
    Store      = $store
    Graph      = $tenant.Directory
    AccessMode = $AccessMode
    StartJob   = { param($Runbook, $Parameters) Write-Information "would start $Runbook $($Parameters | ConvertTo-Json -Compress)" -InformationAction Continue; [guid]::NewGuid().ToString() }
}

# Routes from function.json, longest first so "definitions/{id}/sync" wins over "definitions/{id}".
$routes = foreach ($file in Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'src/Api') -Filter 'function.json' -Recurse -Depth 1) {
    $binding = (Get-Content -Raw -Path $file.FullName | ConvertFrom-Json).bindings | Where-Object { $_.type -eq 'httpTrigger' }
    $names = [regex]::Matches($binding.route, '\{(\w+)\??\}') | ForEach-Object { $_.Groups[1].Value }
    $pattern = '^/api/' + ([regex]::Escape($binding.route) -replace '\\\{(\w+)\??}', '(?<$1>[^/]+)') + '/?$'
    [pscustomobject]@{ Route = $binding.route; Regex = [regex]::new($pattern, 'IgnoreCase'); Names = @($names); Methods = @($binding.methods) }
}
$routes = @($routes | Sort-Object -Property { $_.Route.Length } -Descending)

$principal = if ($Role -eq 'none') { $null } else {
    $json = @{ identityProvider = 'aad'; userId = 'local'; userDetails = $Upn; userRoles = @('anonymous', 'authenticated', $Role) } | ConvertTo-Json -Compress
    [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Information -MessageData "RDG API on http://localhost:$Port/api (role $Role, $AccessMode)" -InformationAction Continue
$served = 0
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $served++
        $path = $context.Request.Url.AbsolutePath
        $method = $context.Request.HttpMethod
        $match = $null
        $route = $routes | Where-Object { $match = $_.Regex.Match($path); $match.Success } | Select-Object -First 1
        if ($route) { $match = $route.Regex.Match($path) }
        $result = if (-not $route) {
            @{ StatusCode = 404; Headers = @{ 'Content-Type' = 'application/json' }; Body = '{"title":"No such route"}' }
        } else {
            $headers = @{}
            foreach ($key in $context.Request.Headers.AllKeys) { $headers[$key] = $context.Request.Headers[$key] }
            if ($principal -and $route.Route -ne 'roles') { $headers['x-ms-client-principal'] = $principal }
            $query = @{}
            foreach ($key in $context.Request.QueryString.AllKeys) { if ($key) { $query[$key] = $context.Request.QueryString[$key] } }
            $params = @{}
            foreach ($name in $route.Names) { $params[$name] = [System.Uri]::UnescapeDataString($match.Groups[$name].Value) }
            $reader = [System.IO.StreamReader]::new($context.Request.InputStream, [System.Text.Encoding]::UTF8)
            $raw = $reader.ReadToEnd()
            $request = @{ Method = $method; Headers = $headers; Query = $query; Params = $params; RawBody = $raw }
            Invoke-DgApiFunction -Route $route.Route -Request $request
        }
        $response = $context.Response
        $response.StatusCode = [int]$result.StatusCode
        foreach ($key in $result.Headers.Keys) {
            if ($key -eq 'Content-Type') { $response.ContentType = $result.Headers[$key] } else { $response.Headers[$key] = [string]$result.Headers[$key] }
        }
        if ($result.Body) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($result.Body)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        $response.Close()
        Write-Information -MessageData "$method $path -> $($result.StatusCode)" -InformationAction Continue
        if ($MaxRequests -and $served -ge $MaxRequests) { break }
    }
} finally {
    $listener.Stop()
}
