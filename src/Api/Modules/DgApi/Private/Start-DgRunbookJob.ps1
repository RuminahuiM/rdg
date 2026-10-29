function Start-DgRunbookJob {
    <#
    .SYNOPSIS
        Starts a job of an Automation runbook (Automation REST API, Job - Create) as the "api"
        identity and returns the job ID.
    .DESCRIPTION
        The "api" identity needs Automation Job Operator on the account and Automation Runbook
        Operator on the two sync runbooks. Tests and the local host pass Context.StartJob instead.
    .EXAMPLE
        Start-DgRunbookJob -Context $Context -Runbook Sync-EntraGroups -Parameters @{ Mode = 'SyncNow'; DefinitionId = $id }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context,

        [Parameter(Mandatory)]
        [ValidateSet('Sync-EntraGroups', 'Sync-ExchangeGroups')]
        [string] $Runbook,

        [Parameter(Mandatory)]
        [hashtable] $Parameters
    )

    if (-not $PSCmdlet.ShouldProcess($Runbook, 'Start job')) { return $null }
    if ($Context.StartJob) { return [string](& $Context.StartJob $Runbook $Parameters) }
    if ($Context.AutomationAccountId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Automation/automationAccounts/[^/]+$') {
        throw 'the app setting DG_AutomationAccountId is missing or not an Automation account resource ID'
    }
    $jobId = [guid]::NewGuid().ToString()
    $token = Invoke-DgEngine -Name Get-DgManagedIdentityToken -Parameters @{ Resource = 'https://management.azure.com/'; ClientId = $Context.ClientId }
    $body = @{ properties = @{ runbook = @{ name = $Runbook }; parameters = $Parameters; runOn = '' } } | ConvertTo-Json -Depth 5 -Compress
    $uri = "https://management.azure.com$($Context.AutomationAccountId)/jobs/$jobId`?api-version=2024-10-23"
    $null = Invoke-RestMethod -Method Put -Uri $uri -Body $body -ContentType 'application/json' -Headers @{ Authorization = "Bearer $($token.Token)" }
    $jobId
}
