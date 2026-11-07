function Get-DgDefinitionOrder {
    <#
    .SYNOPSIS
        Orders definitions so that every definition comes after the ones its memberOf rule uses,
        and finds memberOf cycles.
    .DESCRIPTION
        Dependencies is a hashtable: definition ID -> definition IDs it references. Returns
        Order (IDs that can be evaluated, dependencies first) and Cycles (definition ID -> the
        cycle it is part of, as a list of IDs ending where it started). Definitions that only
        depend on a cycle are in neither: the caller reports them as failed dependencies.
        Kahn's algorithm; ties keep the input order, so results are stable.
    .EXAMPLE
        Get-DgDefinitionOrder -Ids @('a','b') -Dependencies @{ a = @('b'); b = @() }   # Order: b, a
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Ids,

        [Parameter(Mandatory)]
        [hashtable] $Dependencies
    )

    $remaining = [System.Collections.Generic.Dictionary[string, int]]::new()
    $dependents = @{}
    foreach ($id in $Ids) {
        $remaining[$id] = 0
        $dependents[$id] = [System.Collections.Generic.List[string]]::new()
    }
    foreach ($id in $Ids) {
        foreach ($dependency in @($Dependencies[$id])) {
            if ($null -eq $dependency -or -not $remaining.ContainsKey($dependency)) { continue }
            $remaining[$id]++
            $dependents[$dependency].Add($id)
        }
    }

    $order = [System.Collections.Generic.List[string]]::new()
    $ready = [System.Collections.Generic.Queue[string]]::new()
    foreach ($id in $Ids) {
        if ($remaining[$id] -eq 0) { $ready.Enqueue($id) }
    }
    while ($ready.Count -gt 0) {
        $id = $ready.Dequeue()
        $order.Add($id)
        foreach ($dependent in $dependents[$id]) {
            $remaining[$dependent]--
            if ($remaining[$dependent] -eq 0) { $ready.Enqueue($dependent) }
        }
    }

    # Whatever is left is in a cycle or depends on one. Find the cycles by walking dependencies
    # among the leftovers until a definition repeats.
    $leftover = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($id in $Ids) {
        if (-not $order.Contains($id)) { [void]$leftover.Add($id) }
    }
    $cycles = @{}
    foreach ($start in $Ids) {
        if (-not $leftover.Contains($start) -or $cycles.ContainsKey($start)) { continue }
        $path = [System.Collections.Generic.List[string]]::new()
        $current = $start
        while ($null -ne $current -and -not $path.Contains($current)) {
            $path.Add($current)
            $current = @($Dependencies[$current]) | Where-Object { $null -ne $_ -and $leftover.Contains($_) } | Select-Object -First 1
        }
        if ($null -ne $current) {
            $cycle = [string[]]@($path.GetRange($path.IndexOf($current), $path.Count - $path.IndexOf($current))) + $current
            foreach ($member in $cycle) {
                if (-not $cycles.ContainsKey($member)) { $cycles[$member] = $cycle }
            }
        }
    }

    [pscustomobject]@{
        Order  = $order.ToArray()
        Cycles = $cycles
    }
}
