function Get-DgDefinitionGroupId {
    <#
    .SYNOPSIS
        The group a definition manages: target.groupId, or for target mode create the ID the
        engine stored in the status once it created the group. Lower case; $null if none yet.
    .EXAMPLE
        Get-DgDefinitionGroupId -Definition $definition -Status $status
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Definition,

        [AllowNull()]
        [System.Collections.IDictionary] $Status
    )

    $target = $Definition['target']
    $id = if ($target -and $target['mode'] -ne 'create') { [string]$target['groupId'] } elseif ($Status) { [string]$Status['groupId'] } else { '' }
    if ($id) { $id.ToLowerInvariant() } else { $null }
}
