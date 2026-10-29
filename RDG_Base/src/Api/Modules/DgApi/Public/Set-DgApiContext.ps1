function Set-DgApiContext {
    <#
    .SYNOPSIS
        Replaces the API context, for tests and the local development host: an in-memory store,
        a fake directory and a fake job starter instead of Azure.
    .DESCRIPTION
        Keys: Store, Graph, AccessMode, Version, StartJob ({ param($Runbook, $Parameters) } -> job
        ID), Now ({ } -> DateTimeOffset), AutomationAccountId. Missing keys get defaults.
        Pass $null to go back to the app settings.
    .EXAMPLE
        Set-DgApiContext -Context @{ Store = $store; Graph = $tenant.Directory; AccessMode = 'read-write' }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [AllowNull()]
        [hashtable] $Context
    )

    if (-not $PSCmdlet.ShouldProcess('API context', 'Replace')) { return }
    if ($null -eq $Context) {
        $script:DgApiContext = $null
        return
    }
    $defaults = @{
        Graph               = $null
        ConnectGraph        = { param([string] $ClientId) throw "no Graph connection in this context ($ClientId)" }
        ClientId            = ''
        AccessMode          = 'read-write'
        AutomationAccountId = ''
        StartJob            = { param($Runbook, $Parameters) throw "no job starter in this context ($Runbook, $($Parameters.Count) parameters)" }
        Version             = (Get-Module -Name DgEngine).Version.ToString(3)
        Now                 = { [DateTimeOffset]::UtcNow }
        UserCache           = @{}
    }
    foreach ($key in $defaults.Keys) { if (-not $Context.ContainsKey($key)) { $Context[$key] = $defaults[$key] } }
    if (-not $Context.ContainsKey('Store')) { throw 'the context needs a Store' }
    $script:DgApiContext = $Context
}
