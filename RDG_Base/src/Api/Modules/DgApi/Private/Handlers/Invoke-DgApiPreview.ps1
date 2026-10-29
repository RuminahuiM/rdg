function Invoke-DgApiPreview {
    <#
    .SYNOPSIS
        POST /api/preview: what a saved (definitionId), new (definition) or edited (both) definition would do
        now: members, excluded users with reasons, diff to the target group, change-limit verdict
        and compare lists. Uses the engine's Get-DgPreview; the user list is cached per worker for
        five minutes, so a second preview is fast.
    .EXAMPLE
        Invoke-DgApiPreview -Request $Request -Caller $caller -Context $context
    #>
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

    $body = Read-DgRequestBody -Request $Request -Schema PreviewInput
    $data = Get-DgApiStoreData -Context $Context
    $stored = if ($body['definitionId']) { Get-DgStoredDefinition -Context $Context -Id ([string]$body['definitionId']) } else { $null }
    if (-not $body['definition']) {
        $definition = $stored.Definition
        $status = $stored.Status
    } else {
        $requested = $body['definition']
        $check = Test-DgRule -Rule ([string]$requested['rule'])
        if (-not $check.Valid) {
            $errors = foreach ($ruleError in (Get-DgRuleErrorList -Check $check)) {
                [ordered]@{ field = 'definition.rule'; message = $ruleError.message; position = $ruleError.position; line = $ruleError.line; column = $ruleError.column }
            }
            Stop-DgApi -Status 400 -Title 'Rule is not valid' -Type 'validation' -Extra @{ errors = @($errors) }
        }
        # Unsaved changes to a saved definition keep its ID, so the saved copy is left out of the
        # evaluation (otherwise both would claim the same group) and its status still applies.
        $id = if ($stored) { [string]$stored.Definition['id'] } else { 'def-PREV1EW0000000000000000000' }
        $definition = [ordered]@{ id = $id; pk = $id; type = 'definition' }
        foreach ($key in $requested.Keys) { $definition[$key] = $requested[$key] }
        $status = if ($stored) { $stored.Status } else { $null }
    }
    $settings = Invoke-DgEngine -Name Get-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'config'; Id = 'settings'; PartitionKey = 'settings' }
    if (-not $settings) { $settings = @{} }
    $graph = Get-DgApiGraph -Context $Context

    # Users, cached per worker for five minutes per set of fields
    $rules = [string[]]@(@($data.Definitions | ForEach-Object { [string]$_['rule'] }) + @([string]$definition['rule']))
    $fields = Invoke-DgEngine -Name Get-DgSnapshotField -Parameters @{ Rules = $rules }
    $select = [string[]]@(@($fields.Select) + @('mail') | Sort-Object -Unique)
    $key = ($select -join ',') + "|$($fields.ExpandManager)"
    $now = & $Context.Now
    $cached = $Context.UserCache[$key]
    if (-not $cached -or ($now - $cached.At).TotalMinutes -ge 5) {
        $users = Invoke-DgEngine -Name Get-DgDirectoryUser -Parameters @{ Directory = $graph; Select = $select; ExpandManager = [bool]$fields.ExpandManager }
        $cached = @{ At = $now; Users = $users }
        $Context.UserCache.Clear()
        $Context.UserCache[$key] = $cached
    }

    try {
        $preview = Get-DgPreview -Definition $definition -Status $status -Definitions $data.Definitions -Statuses $data.Statuses `
            -Settings $settings -Graph $graph -Users $cached.Users -Now $now
    } catch [System.InvalidOperationException] {
        if ($_.Exception.Data['DgProblem']) { throw }
        Stop-DgApi -Status 400 -Title "The definition can't be previewed" -Detail $_.Exception.Message -Type 'validation'
    }
    New-DgApiResponse -Status 200 -Body $preview
}
