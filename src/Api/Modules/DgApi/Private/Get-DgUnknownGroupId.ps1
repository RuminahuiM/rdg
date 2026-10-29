function Get-DgUnknownGroupId {
    <#
    .SYNOPSIS
        Returns the memberOf group IDs that exist neither as an RDG-managed group nor in Graph.
    .EXAMPLE
        Get-DgUnknownGroupId -Context $Context -GroupIds $check.ReferencedGroupIds -Data $data
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $GroupIds,

        [Parameter(Mandatory)]
        [pscustomobject] $Data
    )

    if (-not $GroupIds.Count) { return }
    $managed = @{}
    foreach ($definition in $Data.Definitions) {
        $id = Get-DgDefinitionGroupId -Definition $definition -Status $Data.Statuses[[string]$definition['id']]
        if ($id) { $managed[$id] = $true }
    }
    $graph = Get-DgApiGraph -Context $Context
    foreach ($groupId in $GroupIds) {
        $id = $groupId.ToLowerInvariant()
        if ($managed.ContainsKey($id)) { continue }
        $group = Invoke-DgEngine -Name Get-DgDirectoryGroup -Parameters @{ Directory = $graph; GroupId = $id }
        if (-not $group) { $id }
    }
}
