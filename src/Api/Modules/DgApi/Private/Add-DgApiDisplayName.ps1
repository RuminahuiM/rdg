function Add-DgApiDisplayName {
    <#
    .SYNOPSIS
        Adds includeUsers, excludeUsers and compareGroup to a definition (GET of one definition),
        so the web app can show names instead of IDs.
    .DESCRIPTION
        One Graph $batch per 20 IDs (User.Read.All and GroupMember.Read.All suffice). If Graph fails, the definition is returned without the names
        (the web app then shows the IDs); the error goes to the warning stream.
    .EXAMPLE
        Add-DgApiDisplayName -Definition $definition -Context $Context
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary] $Definition,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $ids = [string[]]@(@($Definition.includeUserIds) + @($Definition.excludeUserIds) + @($Definition.compareGroupId) | Where-Object { $_ })
    if ($ids.Count -eq 0) {
        return $Definition
    }
    try {
        $graph = Get-DgApiGraph -Context $Context
        $objects = Invoke-DgEngine -Name Get-DgDirectoryObjectById -Parameters @{
            Directory = $graph
            UserIds   = [string[]]@(@($Definition.includeUserIds) + @($Definition.excludeUserIds) | Where-Object { $_ })
            GroupIds  = [string[]]@(@($Definition.compareGroupId) | Where-Object { $_ })
        }
    } catch {
        Write-Warning "Names for definition $($Definition.id) not resolved: $($_.Exception.Message)"
        return $Definition
    }
    $byId = @{}
    foreach ($object in $objects) {
        $id = [string](Invoke-DgEngine -Name Get-DgFieldValue -Parameters @{ Object = $object; Name = 'id' })
        if ($id) { $byId[$id.ToLowerInvariant()] = $object }
    }
    $toUser = {
        param([string] $Id)
        $object = $byId[$Id.ToLowerInvariant()]
        if (-not $object) { return }
        $upn = [string](Invoke-DgEngine -Name Get-DgFieldValue -Parameters @{ Object = $object; Name = 'userPrincipalName' })
        if (-not $upn) { return }
        [ordered]@{ id = $Id; upn = $upn; displayName = [string](Invoke-DgEngine -Name Get-DgFieldValue -Parameters @{ Object = $object; Name = 'displayName' }) }
    }
    $Definition.includeUsers = [object[]]@(foreach ($id in $Definition.includeUserIds) { & $toUser $id })
    $Definition.excludeUsers = [object[]]@(foreach ($id in $Definition.excludeUserIds) { & $toUser $id })
    if ($Definition.compareGroupId -and $byId[([string]$Definition.compareGroupId).ToLowerInvariant()]) {
        $group = $byId[([string]$Definition.compareGroupId).ToLowerInvariant()]
        $Definition.compareGroup = [ordered]@{
            id          = [string]$Definition.compareGroupId
            displayName = [string](Invoke-DgEngine -Name Get-DgFieldValue -Parameters @{ Object = $group; Name = 'displayName' })
        }
    }
    $Definition
}
