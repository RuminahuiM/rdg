function Invoke-DgApiListDefinitionRuns {
    <#
    .SYNOPSIS
        GET /api/definitions/{id}/runs: run records of one definition, newest first.
    .EXAMPLE
        Invoke-DgApiListDefinitionRuns -Request $Request -Caller $caller -Context $context
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

    $stored = Get-DgStoredDefinition -Context $Context -Id (Get-DgRequestValue -Request $Request -Part Params -Name id)
    $id = [string]$stored.Definition['id']
    $runs = foreach ($run in (Invoke-DgEngine -Name Find-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'runs'; Type = 'run' })) {
        if ($run['pk'] -eq $id) { ConvertTo-DgApiRun -Document $run -AutomationAccountId $Context.AutomationAccountId }
    }
    $sorted = [object[]]@($runs | Sort-Object -Property { [string]$_.startedAt }, { [string]$_.id } -Descending)
    New-DgApiResponse -Status 200 -Body (Select-DgPage -Items $sorted -Token (Get-DgRequestValue -Request $Request -Part Query -Name continuationToken))
}
