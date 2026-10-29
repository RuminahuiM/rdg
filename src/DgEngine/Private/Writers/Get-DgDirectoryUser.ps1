function Get-DgDirectoryUser {
    <#
    .SYNOPSIS
        Reads all users with the given Graph fields: the user snapshot of a run.
    .DESCRIPTION
        Always includes id, displayName, userPrincipalName, accountEnabled and userType (the
        implicit filters and reports need them). ExpandManager adds manager { id } for Direct
        Reports rules. Users always come from Graph, also in the Exchange runbook.
    .EXAMPLE
        Get-DgDirectoryUser -Directory $graph -Select @('department', 'onPremisesExtensionAttributes')
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [AllowEmptyCollection()]
        [string[]] $Select = @(),

        [switch] $ExpandManager
    )

    if ($Directory.Kind -eq 'Custom') {
        return , [object[]]@(& $Directory.GetUsers -Select $Select -ExpandManager:$ExpandManager)
    }
    $fields = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($field in @('id', 'displayName', 'userPrincipalName', 'accountEnabled', 'userType') + @($Select)) {
        if ($field) { [void]$fields.Add($field) }
    }
    $uri = '/users?$select=' + ([string[]]@($fields) -join ',') + '&$top=999'
    if ($ExpandManager) { $uri += '&$expand=manager($select=id)' }
    Get-DgGraphCollection -Directory $Directory -Uri $uri
}
