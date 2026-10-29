function Invoke-DgDefinitionEvaluation {
    <#
    .SYNOPSIS
        Computes the desired members of a set of definitions, resolving memberOf references.
    .DESCRIPTION
        For each target definition and every definition it depends on through memberOf:
        - A memberOf group that another definition manages uses that definition's result from
          this same evaluation (rule, filters, includes, excludes), never the group's current
          members, so a chain is never one sync behind. Enabled or not doesn't matter here.
        - Any other group is read once through GroupMemberProvider, with nested members when
          NestedMembers is on (the organisation setting), direct members otherwise.
        - Definitions are evaluated dependencies first. Definitions in a memberOf cycle get an
          error naming the cycle; definitions that depend on a failed one get an error naming it.
        - Two definitions linked to the same group both get an error.
        Errors are per definition; one failing definition never stops the others.

        Definitions are hashtables or objects with Id, Name, Rule, GroupId (null until a created
        group exists), IncludeDisabled, IncludeGuests.

        GroupMemberProvider is called as & $provider -GroupId <id> -Transitive <bool> and returns
        an object with Found (false if the group doesn't exist) and UserIds.
    .EXAMPLE
        Invoke-DgDefinitionEvaluation -Definitions $defs -TargetIds $due -Users $users -Now $now -GroupMemberProvider $provider
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Definitions,

        # Definitions to evaluate; their dependencies are added automatically. Default: all.
        [string[]] $TargetIds,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Users,

        [Parameter(Mandatory)]
        [DateTimeOffset] $Now,

        [bool] $NestedMembers = $true,

        [Parameter(Mandatory)]
        [scriptblock] $GroupMemberProvider
    )

    $field = { param($object, $name) Get-DgFieldValue -Object $object -Name $name }
    $byId = [ordered]@{}
    foreach ($definition in $Definitions) {
        $byId[[string](& $field $definition 'Id')] = $definition
    }
    if (-not $PSBoundParameters.ContainsKey('TargetIds')) {
        $TargetIds = [string[]]@($byId.Keys)
    }
    $nameOf = { param($id) [string](& $field $byId[$id] 'Name') }

    $results = @{}
    $fail = {
        param($id, $message)
        $results[$id] = [pscustomobject]@{
            PSTypeName   = 'Dg.DefinitionResult'
            DefinitionId = $id
            Name         = & $nameOf $id
            Status       = 'Error'
            Error        = $message
            Desired      = $null
            IsTarget     = $TargetIds -contains $id
        }
    }

    # Which definition manages which group; a group may belong to one definition only.
    $managedBy = @{}
    $sharedGroups = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $byId.Keys) {
        $groupId = [string](& $field $byId[$id] 'GroupId')
        if (-not $groupId) { continue }
        $groupId = $groupId.ToLowerInvariant()
        if ($managedBy.ContainsKey($groupId)) { [void]$sharedGroups.Add($groupId) } else { $managedBy[$groupId] = $id }
    }

    # Parse every rule once and collect dependencies.
    $compiled = @{}
    $references = @{}
    $dependencies = @{}
    foreach ($id in $byId.Keys) {
        $references[$id] = @()
        $dependencies[$id] = @()
        try {
            $check = Test-DgRule -Rule ([string](& $field $byId[$id] 'Rule'))
            if (-not $check.Valid) {
                & $fail $id "the rule is not valid: $($check.Errors[0].Message)"
                continue
            }
            $compiled[$id] = ConvertTo-DgCompiledRule -Node $check.Ast
        } catch {
            # A bug in the engine must not take the other definitions down with it.
            & $fail $id "the rule could not be prepared: $($_.Exception.Message)"
            continue
        }
        $references[$id] = [string[]]@($check.ReferencedGroupIds | ForEach-Object { $_.ToLowerInvariant() })
        $dependencies[$id] = [string[]]@($references[$id] | Where-Object { $managedBy.ContainsKey($_) } | ForEach-Object { $managedBy[$_] })
    }
    foreach ($id in $byId.Keys) {
        $groupId = [string](& $field $byId[$id] 'GroupId')
        if ($groupId -and $sharedGroups.Contains($groupId) -and -not $results.ContainsKey($id)) {
            & $fail $id "the group $groupId is linked to more than one definition"
        }
    }

    # Targets plus everything they depend on.
    $needed = [System.Collections.Generic.List[string]]::new()
    $queue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($id in $TargetIds) {
        if ($byId.Contains($id)) { $queue.Enqueue($id) }
    }
    while ($queue.Count -gt 0) {
        $id = $queue.Dequeue()
        if ($needed.Contains($id)) { continue }
        $needed.Add($id)
        foreach ($dependency in $dependencies[$id]) { $queue.Enqueue($dependency) }
    }
    $neededInInputOrder = [string[]]@($byId.Keys | Where-Object { $needed.Contains($_) })

    $plan = Get-DgDefinitionOrder -Ids $neededInInputOrder -Dependencies $dependencies
    foreach ($id in $plan.Cycles.Keys) {
        if (-not $results.ContainsKey($id)) {
            $path = ($plan.Cycles[$id] | ForEach-Object { & $nameOf $_ }) -join ' -> '
            & $fail $id "memberOf cycle: $path"
        }
    }

    $groupMembers = @{}
    $loadGroup = {
        param($groupId)
        if ($groupMembers.ContainsKey($groupId)) { return }
        $loaded = & $GroupMemberProvider -GroupId $groupId -Transitive $NestedMembers
        if (-not $loaded -or -not $loaded.Found) {
            $groupMembers[$groupId] = $null
            return
        }
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($userId in @($loaded.UserIds)) { if ($userId) { [void]$set.Add([string]$userId) } }
        $groupMembers[$groupId] = $set
    }

    $evaluate = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $plan.Order) { $evaluate.Add($id) }
    # Definitions stuck behind a cycle: report the failed dependency.
    foreach ($id in $neededInInputOrder) {
        if (-not $evaluate.Contains($id) -and -not $results.ContainsKey($id)) { $evaluate.Add($id) }
    }

    foreach ($id in $evaluate) {
        if ($results.ContainsKey($id)) { continue }
        $failedDependency = $dependencies[$id] | Where-Object { -not $results.ContainsKey($_) -or $results[$_].Status -ne 'OK' } | Select-Object -First 1
        if ($failedDependency) {
            $reason = if ($results.ContainsKey($failedDependency)) { $results[$failedDependency].Error } else { 'it could not be evaluated' }
            & $fail $id "depends on $(& $nameOf $failedDependency), which failed: $reason"
            continue
        }

        $missing = $null
        foreach ($groupId in $references[$id]) {
            if ($managedBy.ContainsKey($groupId)) {
                $groupMembers[$groupId] = $results[$managedBy[$groupId]].Desired.MemberIds
                continue
            }
            try {
                & $loadGroup $groupId
            } catch {
                $missing = "reading the members of group $groupId failed: $($_.Exception.Message)"
                break
            }
            if ($null -eq $groupMembers[$groupId]) {
                $missing = "the memberOf group $groupId doesn't exist"
                break
            }
        }
        if ($missing) {
            & $fail $id $missing
            continue
        }

        try {
            $context = @{ Now = $Now; GroupMembers = $groupMembers }
            $desired = Get-DgDesiredMember -Compiled $compiled[$id] -Definition $byId[$id] -Users $Users -Context $context
        } catch {
            & $fail $id "evaluating the rule failed: $($_.Exception.Message)"
            continue
        }
        $results[$id] = [pscustomobject]@{
            PSTypeName   = 'Dg.DefinitionResult'
            DefinitionId = $id
            Name         = & $nameOf $id
            Status       = 'OK'
            Error        = $null
            Desired      = $desired
            IsTarget     = $TargetIds -contains $id
        }
    }

    foreach ($id in $byId.Keys) {
        if ($results.ContainsKey($id)) { $results[$id] }
    }
}
