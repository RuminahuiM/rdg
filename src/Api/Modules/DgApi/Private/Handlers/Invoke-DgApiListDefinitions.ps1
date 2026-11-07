function Invoke-DgApiListDefinitions {
    <#
    .SYNOPSIS
        GET /api/definitions: definitions with their status, filtered and sorted by name, 50 per page.
    .EXAMPLE
        Invoke-DgApiListDefinitions -Request $Request -Caller $caller -Context $context
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

    $groupType = Get-DgRequestValue -Request $Request -Part Query -Name groupType
    $result = Get-DgRequestValue -Request $Request -Part Query -Name result
    $enabled = Get-DgRequestValue -Request $Request -Part Query -Name enabled
    $search = Get-DgRequestValue -Request $Request -Part Query -Name search
    if ($groupType -and $groupType -cnotin @('Security', 'Microsoft365', 'MailEnabledSecurity', 'Distribution')) { Stop-DgApi -Status 400 -Title 'Unknown groupType' -Type 'validation' }
    if ($result -and $result -cnotin @('OK', 'Warning', 'Blocked', 'Error', 'DryRun', 'WaitingForApproval')) { Stop-DgApi -Status 400 -Title 'Unknown result' -Type 'validation' }
    if ($enabled -and $enabled -notin @('true', 'false')) { Stop-DgApi -Status 400 -Title 'enabled must be true or false' -Type 'validation' }
    if ($search -and $search.Length -gt 100) { Stop-DgApi -Status 400 -Title 'search is too long' -Type 'validation' }

    $data = Get-DgApiStoreData -Context $Context
    $items = foreach ($document in $data.Definitions) {
        $definition = ConvertTo-DgApiDefinition -Document $document -Status $data.Statuses[[string]$document['id']]
        if ($groupType -and $definition.groupType -cne $groupType) { continue }
        if ($result -and (-not $definition.status -or $definition.status.lastResult -cne $result)) { continue }
        if ($enabled -and $definition.enabled -ne ($enabled -eq 'true')) { continue }
        if ($search) {
            $names = @($definition.name, $definition.target['displayName']) | Where-Object { $_ }
            if (-not ($names | Where-Object { ([string]$_).IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })) { continue }
        }
        $definition
    }
    $sorted = [object[]]@($items | Sort-Object -Property { [string]$_.name }, { [string]$_.id })
    New-DgApiResponse -Status 200 -Body (Select-DgPage -Items $sorted -Token (Get-DgRequestValue -Request $Request -Part Query -Name continuationToken))
}
