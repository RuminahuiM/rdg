#Requires -Version 7.4
<#
.SYNOPSIS
    Helpers for Deploy-Rdg.ps1: plan summary, web config, Azure Resource Manager calls, runbook
    publishing and the smoke test.
.DESCRIPTION
    Functions that call Azure or HTTP take the call as a script block (-Invoke), so
    tests/Deploy runs them without Azure.
#>

Set-StrictMode -Version Latest

$script:AutomationApiVersion = '2024-10-23'
$script:WebApiVersion = '2024-04-01'

#region Pure helpers

function Get-RdgBackendConfig {
    <#
    .SYNOPSIS
        The -backend-config arguments of tofu init for one installation.
    .EXAMPLE
        tofu init (Get-RdgBackendConfig -ResourceGroup rg-rdg-prod-bootstrap -StorageAccount strdgprodbs1a2b -Environment prod)
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9]{3,24}$')]
        [string] $StorageAccount,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z0-9]{2,7}$')]
        [string] $Environment
    )

    [string[]]@(
        "-backend-config=resource_group_name=$ResourceGroup"
        "-backend-config=storage_account_name=$StorageAccount"
        '-backend-config=container_name=tfstate'
        "-backend-config=key=rdg-$Environment.tfstate"
    )
}

function Get-RdgPlanSummary {
    <#
    .SYNOPSIS
        Counts and lists the changes of a plan (tofu show -json), replaces and deletes first.
    .DESCRIPTION
        Returns Create, Update, Replace, Delete, Attention (replaces + deletes), Changes and a
        Markdown summary for the pipeline run.
    .EXAMPLE
        Get-RdgPlanSummary -PlanJson (tofu show -json rdg.tfplan | Out-String)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $PlanJson
    )

    $plan = $PlanJson | ConvertFrom-Json -Depth 100
    $changes = [System.Collections.Generic.List[object]]::new()
    $resourceChanges = if ($plan.PSObject.Properties['resource_changes']) { @($plan.resource_changes) } else { @() }
    foreach ($change in $resourceChanges) {
        $actions = [string[]]@($change.change.actions)
        $action = switch -Exact (($actions | Sort-Object) -join ',') {
            'create' { 'create' }
            'update' { 'update' }
            'delete' { 'delete' }
            'create,delete' { 'replace' }
            default { $null }   # no-op, read
        }
        if ($action) { $changes.Add([pscustomobject]@{ Address = [string]$change.address; Action = $action }) }
    }
    $count = { param($name) @($changes | Where-Object Action -EQ $name).Count }
    $summary = [pscustomobject]@{
        Create    = & $count 'create'
        Update    = & $count 'update'
        Replace   = & $count 'replace'
        Delete    = & $count 'delete'
        Attention = (& $count 'replace') + (& $count 'delete')
        Changes   = $changes.ToArray()
        Markdown  = ''
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# OpenTofu plan')
    $lines.Add('')
    $lines.Add("$($summary.Create) to create, $($summary.Update) to update, $($summary.Replace) to replace, $($summary.Delete) to delete.")
    if ($summary.Attention -gt 0) {
        $lines.Add('')
        $lines.Add('**Replaces and deletes - check these before approving:**')
        $lines.Add('')
        foreach ($item in $changes | Where-Object { $_.Action -in @('replace', 'delete') }) { $lines.Add("- $($item.Action): ``$($item.Address)``") }
    }
    $other = @($changes | Where-Object { $_.Action -in @('create', 'update') })
    if ($other.Count -gt 0) {
        $lines.Add('')
        $lines.Add('Other changes:')
        $lines.Add('')
        foreach ($item in $other) { $lines.Add("- $($item.Action): ``$($item.Address)``") }
    }
    if ($changes.Count -eq 0) { $lines.Add(''); $lines.Add('No infrastructure changes.') }
    $summary.Markdown = ($lines -join "`n") + "`n"
    $summary
}

function Set-RdgWebConfig {
    <#
    .SYNOPSIS
        Fills the deployment placeholders in staticwebapp.config.json.
    .DESCRIPTION
        __TENANT_ID__ (issuer URL) and __KEY_VAULT_NAME__ (Key Vault reference of the sign-in
        certificate). Fails when a placeholder is left or the result isn't valid JSON.
    .EXAMPLE
        Set-RdgWebConfig -Path ./web/staticwebapp.config.json -TenantId $tenant -KeyVaultName kv-rdg-prod-1a2b
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string] $TenantId,

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$')]
        [string] $KeyVaultName
    )

    $text = Get-Content -Raw -LiteralPath $Path
    $text = $text.Replace('__TENANT_ID__', $TenantId.ToLowerInvariant()).Replace('__KEY_VAULT_NAME__', $KeyVaultName)
    if ($text -match '__[A-Z_]+__') { throw "staticwebapp.config.json still has the placeholder $($Matches[0])" }
    $null = $text | ConvertFrom-Json -Depth 50
    if ($PSCmdlet.ShouldProcess($Path, 'Fill deployment placeholders')) {
        Set-Content -LiteralPath $Path -Value $text -NoNewline
    }
}

function Get-RdgRunbookVersion {
    <#
    .SYNOPSIS
        The RDG version a built runbook was stamped with, or $null.
    .EXAMPLE
        Get-RdgRunbookVersion -Content (Get-Content -Raw ./runbooks/Sync-EntraGroups.ps1)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string] $Content
    )

    if ($Content -match "(?m)^\s*\`$script:DgEngineVersion\s*=\s*'([^']+)'") { return $Matches[1] }
    $null
}

function Get-RdgEncryptionSetting {
    <#
    .SYNOPSIS
        The settings OpenTofu needs before it reads any state: state_key_vault_name and
        state_key_name from the settings file.
    .DESCRIPTION
        The encryption block is evaluated by every tofu command (init, plan, show, apply, output),
        including the ones that take no -var-file, so Deploy-Rdg.ps1 passes these two as
        TF_VAR_ environment variables.
    .EXAMPLE
        Get-RdgEncryptionSetting -SettingsText (Get-Content -Raw ./settings/prod.tfvars)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $SettingsText
    )

    $values = @{ state_key_name = 'rdg-state' }
    foreach ($name in @('state_key_vault_name', 'state_key_name')) {
        if ($SettingsText -match "(?m)^\s*$name\s*=\s*`"([^`"]*)`"") { if ($Matches[1]) { $values[$name] = $Matches[1] } }
    }
    if (-not $values.ContainsKey('state_key_vault_name')) {
        throw 'state_key_vault_name is empty in the settings file; bootstrap stage 1 prints it.'
    }
    $values
}

#endregion

#region Azure Resource Manager

function Invoke-RdgArmRequest {
    <#
    .SYNOPSIS
        One Azure Resource Manager call; returns StatusCode, Headers and Content (parsed JSON
        when the answer is JSON).
    .DESCRIPTION
        Path is relative to https://management.azure.com and includes api-version. Invoke
        defaults to Invoke-WebRequest with a token from Get-AzAccessToken. Fails on 4xx and 5xx.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'PUT', 'POST', 'PATCH', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Path,

        [object] $Body,

        [string] $ContentType = 'application/json',

        [scriptblock] $Invoke = {
            param($Method, $Uri, $Body, $ContentType)
            $token = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com/' -ErrorAction Stop).Token
            if ($token -is [securestring]) { $token = ConvertFrom-SecureString -SecureString $token -AsPlainText }
            $request = @{
                Method = $Method; Uri = $Uri; Headers = @{ Authorization = "Bearer $token" }
                SkipHttpErrorCheck = $true; ErrorAction = 'Stop'
            }
            if ($null -ne $Body) { $request.Body = $Body; $request.ContentType = $ContentType }
            $response = Invoke-WebRequest @request
            # Without a Content-Type (runbook content comes back without one) Invoke-WebRequest
            # returns the body as bytes; [string] on bytes gives a list of numbers, not the text.
            $text = if ($response.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
            [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Headers = $response.Headers; Content = $text }
        }
    )

    $uri = if ($Path -match '^https://') { $Path } else { "https://management.azure.com$Path" }
    $payload = if ($null -eq $Body -or $Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
    $response = & $Invoke $Method $uri $payload $ContentType
    $content = $response.Content
    if ($content -and $content.TrimStart().StartsWith('{')) { $content = $content | ConvertFrom-Json -Depth 50 }
    if ($response.StatusCode -ge 400) {
        $detail = if ($content -is [pscustomobject] -and $content.PSObject.Properties['error']) { "$($content.error.code): $($content.error.message)" } else { [string]$response.Content }
        throw "$Method $Path failed with HTTP $($response.StatusCode): $detail"
    }
    [pscustomobject]@{ StatusCode = $response.StatusCode; Headers = $response.Headers; Content = $content }
}

function Wait-RdgArmOperation {
    <#
    .SYNOPSIS
        Waits for an asynchronous Azure Resource Manager operation (HTTP 202 with a Location or
        Azure-AsyncOperation header) to finish.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Response,

        [int] $TimeoutSeconds = 300,

        [int] $IntervalSeconds = 5,

        [scriptblock] $Invoke
    )

    if ($Response.StatusCode -ne 202) { return $Response }
    $header = {
        param($name)
        if ($null -eq $Response.Headers) { return $null }
        foreach ($key in @($Response.Headers.Keys)) { if ($key -ieq $name) { return [string](@($Response.Headers[$key])[0]) } }
        $null
    }
    $asyncUrl = & $header 'Azure-AsyncOperation'
    $location = & $header 'Location'
    if (-not $asyncUrl -and -not $location) { return $Response }
    $call = @{ Method = 'GET'; Path = $(if ($asyncUrl) { $asyncUrl } else { $location }) }
    if ($Invoke) { $call.Invoke = $Invoke }
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $poll = Invoke-RdgArmRequest @call
        if ($asyncUrl) {
            $status = if ($poll.Content -is [pscustomobject] -and $poll.Content.PSObject.Properties['status']) { [string]$poll.Content.status } else { '' }
            if ($status -eq 'Succeeded') { return $poll }
            if ($status -in @('Failed', 'Canceled')) { throw "operation $status`: $($call.Path)" }
        } elseif ($poll.StatusCode -ne 202) {
            return $poll
        }
        if ([DateTimeOffset]::UtcNow -gt $deadline) { throw "operation didn't finish within $TimeoutSeconds s: $($call.Path)" }
        Start-Sleep -Seconds $IntervalSeconds
    }
}

function Publish-RdgRunbook {
    <#
    .SYNOPSIS
        Replaces a runbook's draft with the built file and publishes it.
    .DESCRIPTION
        Uses the draft and publish operations of the runbook, so the runbook keeps everything
        OpenTofu set (runtime environment, logging, schedules). Returns the published version.
    .EXAMPLE
        Publish-RdgRunbook -AutomationAccountId $id -Name Sync-EntraGroups -Content $text
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Automation/automationAccounts/[^/]+$')]
        [string] $AutomationAccountId,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Content,

        [int] $IntervalSeconds = 5,

        [scriptblock] $Invoke
    )

    $version = Get-RdgRunbookVersion -Content $Content
    if (-not $version) { throw "$Name is not a built runbook (no DgEngine version stamp)" }
    $arm = @{}
    if ($Invoke) { $arm.Invoke = $Invoke }
    $base = "$AutomationAccountId/runbooks/$Name"
    if ($PSCmdlet.ShouldProcess($Name, "Publish runbook $version")) {
        $draft = Invoke-RdgArmRequest @arm -Method PUT -Path "$base/draft/content?api-version=$script:AutomationApiVersion" -Body $Content -ContentType 'text/powershell'
        [void](Wait-RdgArmOperation @arm -Response $draft -IntervalSeconds $IntervalSeconds)
        $publish = Invoke-RdgArmRequest @arm -Method POST -Path "$base/publish?api-version=$script:AutomationApiVersion"
        [void](Wait-RdgArmOperation @arm -Response $publish -IntervalSeconds $IntervalSeconds)
    }
    $version
}

#endregion

#region Smoke test

function Test-RdgDeployment {
    <#
    .SYNOPSIS
        The smoke test: health reports the version, protected endpoints refuse anonymous calls,
        the published runbooks carry the version.
    .DESCRIPTION
        Returns one result per check (Name, Passed, Detail). Http does one anonymous GET without
        following redirects and returns StatusCode and Content. RunbookContent returns the
        published content of a runbook.
    .EXAMPLE
        Test-RdgDeployment -WebUrl https://x.azurestaticapps.net -Version 1.0.0 -Runbook Sync-EntraGroups -RunbookContent $get
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://')]
        [string] $WebUrl,

        [Parameter(Mandatory)]
        [string] $Version,

        [string[]] $Runbook = @(),

        [scriptblock] $RunbookContent,

        [scriptblock] $Http = {
            param($Uri)
            # HttpClient without automatic redirects: Invoke-WebRequest -MaximumRedirection 0 throws
            # on a 3xx answer instead of returning it, and a redirect to sign-in is a valid answer here.
            $handler = [System.Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect = $false
            $client = [System.Net.Http.HttpClient]::new($handler)
            $client.Timeout = [TimeSpan]::FromSeconds(100)
            try {
                $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
                [pscustomobject]@{
                    StatusCode = [int]$response.StatusCode
                    Content    = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    Location   = [string]$response.Headers.Location
                }
            } finally {
                $client.Dispose()
                $handler.Dispose()
            }
        }
    )

    $base = $WebUrl.TrimEnd('/')
    $health = & $Http "$base/api/health"
    $reported = $null
    try { $reported = [string](([string]$health.Content | ConvertFrom-Json).version) } catch { $reported = $null }
    [pscustomobject]@{
        Name   = 'health reports the version'
        Passed = $health.StatusCode -eq 200 -and $reported -eq $Version
        Detail = "HTTP $($health.StatusCode)$(if ($health.PSObject.Properties['Location'] -and $health.Location) { " to $($health.Location)" }), version '$reported', expected '$Version'"
    }

    $anonymous = & $Http "$base/api/definitions"
    [pscustomobject]@{
        Name   = 'anonymous call to a protected endpoint is refused'
        Passed = $anonymous.StatusCode -in @(401, 302, 403)
        Detail = "HTTP $($anonymous.StatusCode)"
    }

    foreach ($name in $Runbook) {
        $published = Get-RdgRunbookVersion -Content ([string](& $RunbookContent $name))
        [pscustomobject]@{
            Name   = "runbook $name is published with the version"
            Passed = $published -eq $Version
            Detail = "published '$published', expected '$Version'"
        }
    }
}

function Get-RdgAlertReceiverStatus {
    <#
    .SYNOPSIS
        Lists the email receivers of the alert action group with their status, for the smoke test.
    .DESCRIPTION
        Azure sends no alert mail to an address until its owner confirms the verification mail
        Azure sent when the action group was created. Returns Email, Status and Confirmed per
        receiver (Confirmed when the status is Enabled).
    .EXAMPLE
        Get-RdgAlertReceiverStatus -ActionGroup (Invoke-RdgArmRequest -Method GET -Path "$id?api-version=2023-01-01").Content
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $ActionGroup
    )

    $properties = if ($ActionGroup -is [System.Collections.IDictionary]) { $ActionGroup['properties'] } else { $ActionGroup.properties }
    $receivers = if ($null -eq $properties) { @() } elseif ($properties -is [System.Collections.IDictionary]) { @($properties['emailReceivers']) } else { @($properties.emailReceivers) }
    foreach ($receiver in $receivers) {
        if ($null -eq $receiver) { continue }
        $email = if ($receiver -is [System.Collections.IDictionary]) { [string]$receiver['emailAddress'] } else { [string]$receiver.emailAddress }
        $status = if ($receiver -is [System.Collections.IDictionary]) { [string]$receiver['status'] } else { [string]$receiver.status }
        [pscustomobject]@{ Email = $email; Status = $status; Confirmed = $status -eq 'Enabled' }
    }
}

#endregion

Export-ModuleMember -Function @(
    'Get-RdgBackendConfig'
    'Get-RdgPlanSummary'
    'Get-RdgEncryptionSetting'
    'Set-RdgWebConfig'
    'Get-RdgRunbookVersion'
    'Invoke-RdgArmRequest'
    'Wait-RdgArmOperation'
    'Publish-RdgRunbook'
    'Test-RdgDeployment'
    'Get-RdgAlertReceiverStatus'
)
