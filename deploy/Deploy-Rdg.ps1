#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '3.0.0' }
<#
.SYNOPSIS
    The steps of the RDG deploy pipeline (deploy/azure-pipelines.yml), kept out of YAML so they
    can be read, tested and run by hand.
.DESCRIPTION
    Runs from an unpacked release bundle (this script lives in <bundle>/deploy), signed in to
    Azure with Az (the pipeline's AzurePowerShell task does that with the service connection).
      Plan        tofu init and tofu plan with the settings file; writes the encrypted plan and a
                  Markdown summary, and warns when the plan replaces or deletes something.
      Apply       tofu apply of that plan; writes the OpenTofu outputs (names, no secrets).
      DeployCode  imports and publishes the runbooks; uploads api.zip and restarts the API.
      DeployWeb   fills staticwebapp.config.json and uploads the web app; the deployment token
                  is fetched here and lives only in this step.
      SmokeTest   health reports the version, anonymous calls are refused, runbooks carry the
                  version; lists the alert mail receivers and warns about unconfirmed ones.
    Reference: CI/CD design ("Deploy pipeline").
.EXAMPLE
    ./deploy/Deploy-Rdg.ps1 -Step Plan -SettingsFile ../settings/prod.tfvars -Environment prod `
        -BackendResourceGroup rg-rdg-prod-bootstrap -BackendStorageAccount strdgprodbs1a2b
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Plan', 'Apply', 'DeployCode', 'DeployWeb', 'SmokeTest')]
    [string] $Step,

    # Unpacked release bundle. Defaults to the folder above this script.
    [string] $BundlePath = (Join-Path -Path $PSScriptRoot -ChildPath '..'),

    [string] $SettingsFile,

    [ValidatePattern('^[a-z0-9]{2,7}$')]
    [string] $Environment,

    [string] $BackendResourceGroup,

    [string] $BackendStorageAccount,

    # Plan file (written by Plan, read by Apply). The Markdown summary goes next to it.
    [string] $PlanPath = (Join-Path -Path (Get-Location) -ChildPath 'rdg.tfplan'),

    # OpenTofu outputs as JSON (written by Apply, read by the later steps).
    [string] $OutputsPath = (Join-Path -Path (Get-Location) -ChildPath 'rdg-outputs.json'),

    # Smoke test: how long to wait for the API to report the new version.
    [int] $SmokeTimeoutSeconds = 600
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'RdgDeploy.psm1') -Force

$BundlePath = (Resolve-Path -Path $BundlePath).Path
# tofu runs with -chdir=infra, so every path it gets must be absolute.
$PlanPath = [System.IO.Path]::GetFullPath($PlanPath)
$OutputsPath = [System.IO.Path]::GetFullPath($OutputsPath)
$version = (Get-Content -Raw -Path (Join-Path -Path $BundlePath -ChildPath 'VERSION')).Trim()
$infra = Join-Path -Path $BundlePath -ChildPath 'infra'
$context = Get-AzContext
if (-not $context) { throw 'Not signed in to Azure (Connect-AzAccount, or run inside the AzurePowerShell task).' }

function Write-Step {
    param([string] $Message)
    Write-Information -MessageData $Message -InformationAction Continue
}

function Invoke-Tofu {
    # Runs tofu in infra/ and fails on a non-zero exit code. Output goes to the log.
    $arguments = @("-chdir=$infra") + $args
    & tofu @arguments
    if ($LASTEXITCODE -ne 0) { throw "tofu $($args[0]) failed with exit code $LASTEXITCODE" }
}

function Initialize-Tofu {
    param([string] $Name, [string] $ResourceGroup, [string] $StorageAccount, [string] $Settings)
    if (-not $Name -or -not $ResourceGroup -or -not $StorageAccount -or -not $Settings) {
        throw "-Environment, -BackendResourceGroup, -BackendStorageAccount and -SettingsFile are required for $Step"
    }
    # State encryption is configured before any state is read, by every tofu command; the two
    # values it needs come from the settings file as environment variables.
    $encryption = Get-RdgEncryptionSetting -SettingsText (Get-Content -Raw -Path $Settings)
    $env:TF_VAR_state_key_vault_name = $encryption.state_key_vault_name
    $env:TF_VAR_state_key_name = $encryption.state_key_name
    # OpenTofu (backend, provider and the state key provider) signs in as the pipeline's service
    # principal. In the pipeline, workload identity federation comes from the service connection
    # (ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID, SYSTEM_ACCESSTOKEN, SYSTEM_OIDCREQUESTURI); by hand,
    # from the Azure CLI.
    $env:ARM_USE_AZUREAD = 'true'
    if ($env:ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID) {
        $env:ARM_SUBSCRIPTION_ID = $context.Subscription.Id
        $env:ARM_TENANT_ID = $context.Tenant.Id
        $env:ARM_USE_OIDC = 'true'
        $env:ARM_USE_CLI = 'false'
        $env:ARM_CLIENT_ID = $context.Account.Id
        $env:ARM_OIDC_AZURE_SERVICE_CONNECTION_ID = $env:ARM_ADO_PIPELINE_SERVICE_CONNECTION_ID
        foreach ($name in @('SYSTEM_ACCESSTOKEN', 'SYSTEM_OIDCREQUESTURI')) {
            if (-not [Environment]::GetEnvironmentVariable($name)) { throw "$name is not set; map it in the pipeline step's env." }
        }
    } else {
        # Azure CLI: current az versions refuse a token request that names both tenant and
        # subscription, which the state key provider sends when ARM_SUBSCRIPTION_ID is set. So
        # tenant and subscription come from the CLI login (az account set below); the provider
        # takes the CLI's default subscription. Check that it is the same tenant as Az's.
        Remove-Item -Path Env:ARM_TENANT_ID, Env:ARM_SUBSCRIPTION_ID -ErrorAction SilentlyContinue
        $cliTenant = (& az account show --query tenantId -o tsv 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $cliTenant) { throw 'Azure CLI is not signed in. Run az login --tenant <tenant ID> first.' }
        if ($cliTenant.Trim() -ne $context.Tenant.Id) { throw "Azure CLI is signed in to tenant $cliTenant, Az PowerShell to $($context.Tenant.Id); sign both in to the same tenant." }
        & az account set --subscription $context.Subscription.Id
        if ($LASTEXITCODE -ne 0) { throw "az account set --subscription $($context.Subscription.Id) failed" }
    }
    $backend = Get-RdgBackendConfig -ResourceGroup $ResourceGroup -StorageAccount $StorageAccount -Environment $Name
    Invoke-Tofu init -input=false -no-color @backend
}

function Read-TofuOutput {
    if (-not (Test-Path -Path $OutputsPath)) { throw "No OpenTofu outputs at $OutputsPath; the Apply step writes them." }
    $raw = Get-Content -Raw -Path $OutputsPath | ConvertFrom-Json -Depth 20
    $values = @{}
    foreach ($property in $raw.PSObject.Properties) { $values[$property.Name] = $property.Value.value }
    $values
}

Write-Step "RDG $version - $Step"
switch ($Step) {
    'Plan' {
        if (-not $SettingsFile) { throw '-SettingsFile is required for Plan' }
        $settings = (Resolve-Path -Path $SettingsFile).Path
        $null = New-Item -Path (Split-Path -Path $PlanPath -Parent) -ItemType Directory -Force
        Initialize-Tofu -Name $Environment -ResourceGroup $BackendResourceGroup -StorageAccount $BackendStorageAccount -Settings $settings
        Invoke-Tofu plan -input=false -no-color "-var-file=$settings" "-var=rdg_version=$version" "-out=$PlanPath"
        $json = & tofu "-chdir=$infra" show -json $PlanPath
        if ($LASTEXITCODE -ne 0) { throw 'tofu show failed' }
        $summary = Get-RdgPlanSummary -PlanJson ($json -join "`n")
        $markdown = "$PlanPath.md"
        Set-Content -Path $markdown -Value $summary.Markdown
        Write-Step "##vso[task.uploadsummary]$markdown"
        Write-Step "Plan: $($summary.Create) create, $($summary.Update) update, $($summary.Replace) replace, $($summary.Delete) delete"
        if ($summary.Attention -gt 0) {
            Write-Step "##vso[task.logissue type=warning]The plan replaces or deletes $($summary.Attention) resource(s). Read the summary before approving."
        }
    }

    'Apply' {
        if (-not (Test-Path -Path $PlanPath)) { throw "No plan at $PlanPath" }
        if (-not $SettingsFile) { throw '-SettingsFile is required for Apply (state encryption)' }
        Initialize-Tofu -Name $Environment -ResourceGroup $BackendResourceGroup -StorageAccount $BackendStorageAccount -Settings (Resolve-Path -Path $SettingsFile).Path
        Invoke-Tofu apply -input=false -no-color $PlanPath
        $outputs = & tofu "-chdir=$infra" output -json
        if ($LASTEXITCODE -ne 0) { throw 'tofu output failed' }
        Set-Content -Path $OutputsPath -Value ($outputs -join "`n")
    }

    'DeployCode' {
        $out = Read-TofuOutput
        $subscription = $context.Subscription.Id
        $group = [string]$out.resource_group_name
        $automationId = "/subscriptions/$subscription/resourceGroups/$group/providers/Microsoft.Automation/automationAccounts/$($out.automation_account_name)"
        foreach ($file in Get-ChildItem -Path (Join-Path -Path $BundlePath -ChildPath 'runbooks') -Filter '*.ps1' | Sort-Object -Property Name) {
            $published = Publish-RdgRunbook -AutomationAccountId $automationId -Name $file.BaseName -Content (Get-Content -Raw -Path $file.FullName)
            Write-Step "Runbook $($file.BaseName) published ($published)"
        }

        # The Function App runs from packages/api.zip (WEBSITE_RUN_FROM_PACKAGE, set by OpenTofu).
        # Plain REST upload with a token: New-AzStorageContext -UseConnectedAccount starts a background
        # token renewer that kills the whole PowerShell process when the network drops later.
        $storageToken = (Get-AzAccessToken -ResourceUrl 'https://storage.azure.com/' -ErrorAction Stop).Token
        if ($storageToken -is [securestring]) { $storageToken = ConvertFrom-SecureString -SecureString $storageToken -AsPlainText }
        $blobUri = "https://$($out.storage_account_name).blob.core.windows.net/packages/api.zip"
        $upload = Invoke-WebRequest -Method PUT -Uri $blobUri -InFile (Join-Path -Path $BundlePath -ChildPath 'api/api.zip') -ContentType 'application/zip' -SkipHttpErrorCheck -Headers @{
            Authorization    = "Bearer $storageToken"
            'x-ms-version'   = '2021-08-06'
            'x-ms-blob-type' = 'BlockBlob'
        }
        if ([int]$upload.StatusCode -ne 201) { throw "Uploading api.zip failed with HTTP $([int]$upload.StatusCode): $($upload.Content)" }
        $site = "/subscriptions/$subscription/resourceGroups/$group/providers/Microsoft.Web/sites/$($out.function_app_name)"
        [void](Invoke-RdgArmRequest -Method POST -Path "$site/restart?api-version=2024-04-01")
        # Right after the restart the host isn't up yet and the sync answers 400 "ServiceUnavailable
        # from host runtime"; retry for up to 5 minutes.
        for ($attempt = 1; ; $attempt++) {
            try {
                [void](Invoke-RdgArmRequest -Method POST -Path "$site/syncfunctiontriggers?api-version=2024-04-01")
                break
            } catch {
                if ($attempt -ge 10 -or "$_" -notmatch 'ServiceUnavailable|HTTP 5\d\d') { throw }
                Write-Step "The API host is still starting; syncing the triggers again in 30 s ($attempt/10)"
                Start-Sleep -Seconds 30
            }
        }
        Write-Step "API package uploaded to $($out.storage_account_name)/packages/api.zip; $($out.function_app_name) restarted"
    }

    'DeployWeb' {
        $out = Read-TofuOutput
        $staging = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "rdg-web-$([guid]::NewGuid())"
        Copy-Item -Path (Join-Path -Path $BundlePath -ChildPath 'web') -Destination $staging -Recurse
        try {
            Set-RdgWebConfig -Path (Join-Path -Path $staging -ChildPath 'staticwebapp.config.json') -TenantId $context.Tenant.Id -KeyVaultName ([string]$out.key_vault_name)
            $siteId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$($out.resource_group_name)/providers/Microsoft.Web/staticSites/$($out.static_web_app_name)"
            $secrets = Invoke-RdgArmRequest -Method POST -Path "$siteId/listSecrets?api-version=2024-04-01"
            # The token goes to the CLI through its environment only; it is never written or logged.
            $env:SWA_CLI_DEPLOYMENT_TOKEN = [string]$secrets.Content.properties.apiKey
            try {
                & npx --yes '@azure/static-web-apps-cli@2.0.10' deploy $staging --env production
                if ($LASTEXITCODE -ne 0) { throw "swa deploy failed with exit code $LASTEXITCODE" }
            } finally {
                Remove-Item -Path Env:SWA_CLI_DEPLOYMENT_TOKEN -ErrorAction SilentlyContinue
            }
        } finally {
            Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Step "Web app deployed to $($out.web_url)"
    }

    'SmokeTest' {
        $out = Read-TofuOutput
        $automationId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$($out.resource_group_name)/providers/Microsoft.Automation/automationAccounts/$($out.automation_account_name)"
        $runbooks = @(Get-ChildItem -Path (Join-Path -Path $BundlePath -ChildPath 'runbooks') -Filter '*.ps1' | ForEach-Object BaseName)
        $content = {
            param($Name)
            (Invoke-RdgArmRequest -Method GET -Path "$automationId/runbooks/$Name/content?api-version=2024-10-23").Content
        }.GetNewClosure()
        # A cold start after the restart can take a few minutes; retry until the version shows.
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds($SmokeTimeoutSeconds)
        do {
            $results = @(Test-RdgDeployment -WebUrl ([string]$out.web_url) -Version $version -Runbook $runbooks -RunbookContent $content)
            $failed = @($results | Where-Object { -not $_.Passed })
            if ($failed.Count -eq 0 -or [DateTimeOffset]::UtcNow -gt $deadline) { break }
            Write-Step "Waiting for the deployment: $($failed[0].Name) ($($failed[0].Detail))"
            Start-Sleep -Seconds 30
        } while ($true)
        foreach ($result in $results) { Write-Step "$(if ($result.Passed) { 'PASS' } else { 'FAIL' })  $($result.Name): $($result.Detail)" }

        # Alert mail goes only to confirmed addresses. Not a failure (the owner confirms by mail),
        # but said on every smoke test until it is done.
        if ($out.ContainsKey('action_group_id') -and $out['action_group_id']) {
            try {
                $group = (Invoke-RdgArmRequest -Method GET -Path "$($out.action_group_id)?api-version=2023-01-01").Content
                foreach ($receiver in @(Get-RdgAlertReceiverStatus -ActionGroup $group)) {
                    Write-Step "$(if ($receiver.Confirmed) { 'NOTE' } else { 'TODO' })  alert mail to $($receiver.Email): $($receiver.Status)"
                    if (-not $receiver.Confirmed) {
                        Write-Warning -Message "Alert mail to $($receiver.Email) is not confirmed yet: no alert reaches it. Confirm the verification mail from Azure (Monitor > Alerts > Action groups > Resend verification emails)."
                    }
                }
            } catch {
                Write-Warning -Message "Could not read the alert receivers: $($_.Exception.Message)"
            }
        }
        if ($failed.Count -gt 0) { throw "Smoke test failed: $(($failed | ForEach-Object Name) -join '; ')" }
    }
}
