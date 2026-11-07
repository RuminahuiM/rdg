function Invoke-DgApiListRuns {
    <#
    .SYNOPSIS
        GET /api/runs: latest runs across all definitions (Activity), filtered by result, runbook
        and start time, newest first.
    .EXAMPLE
        Invoke-DgApiListRuns -Request $Request -Caller $caller -Context $context
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Named after the OpenAPI operationId.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Common handler signature.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [AllowNull()]
        [pscustomobject] $Caller,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $result = Get-DgRequestValue -Request $Request -Part Query -Name result
    $runbook = Get-DgRequestValue -Request $Request -Part Query -Name runbook
    $sinceText = Get-DgRequestValue -Request $Request -Part Query -Name since
    if ($result -and $result -cnotin @('OK', 'Warning', 'Blocked', 'Error', 'DryRun', 'WaitingForApproval', 'SkippedTick', 'Paused')) { Stop-DgApi -Status 400 -Title 'Unknown result' -Type 'validation' }
    if ($runbook -and $runbook -cnotin @('Entra', 'Exchange')) { Stop-DgApi -Status 400 -Title 'Unknown runbook' -Type 'validation' }
    $since = $null
    if ($sinceText) {
        $parsed = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($sinceText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
            Stop-DgApi -Status 400 -Title 'since must be an ISO 8601 time' -Type 'validation'
        }
        $since = $parsed
    }
    $runs = foreach ($run in (Invoke-DgEngine -Name Find-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'runs'; Type = 'run' })) {
        if ($result -and $run['result'] -cne $result) { continue }
        if ($runbook -and $run['runbook'] -cne $runbook) { continue }
        if ($since) {
            $started = Invoke-DgEngine -Name ConvertFrom-DgTimestamp -Parameters @{ Value = $run['startedAt'] }
            if ($started -lt $since) { continue }
        }
        ConvertTo-DgApiRun -Document $run -AutomationAccountId $Context.AutomationAccountId
    }
    $sorted = [object[]]@($runs | Sort-Object -Property { [string]$_.startedAt }, { [string]$_.id } -Descending)
    New-DgApiResponse -Status 200 -Body (Select-DgPage -Items $sorted -Token (Get-DgRequestValue -Request $Request -Part Query -Name continuationToken))
}
