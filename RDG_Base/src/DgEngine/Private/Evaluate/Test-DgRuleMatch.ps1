function Test-DgRuleMatch {
    <#
    .SYNOPSIS
        Evaluates a compiled rule for one user.
    .DESCRIPTION
        Semantics (see the Engine design):
        - Missing values count as null. -eq null / -ne null test for that.
        - Text comparisons ignore case. A null value never equals, starts with, ends with,
          contains, matches or is in anything; the negated operators (-ne, -notStartsWith,
          -notEndsWith, -notContains, -notMatch, -notIn) are exactly the opposite, so they are
          true for null.
        - Dates compare as points in time; system.now is $Context.Now plus the offset.
        - -any is true if one item matches; -all is true if every item matches (also when the
          collection is empty, as in Entra's example "-all (assignedPlan.servicePlanId -eq null)").
        - memberOf: true if the user is a member of any listed group. Members come from
          $Context.GroupMembers (group ID -> set of user IDs), filled by the group resolver.
        - Direct Reports: the user's manager is the given ID, or the user is that manager
          (Entra adds the manager to the group too).
        -and and -or short-circuit.
        A regex that runs longer than 100 ms throws; the definition then ends in Error.
    .EXAMPLE
        Test-DgRuleMatch -Node $compiled -User $user -Context @{ Now = [DateTimeOffset]::UtcNow; GroupMembers = @{} }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [object] $User,

        [Parameter(Mandatory)]
        [hashtable] $Context,

        # Current item inside -any/-all.
        [object] $Item
    )

    switch ($Node.Kind) {
        'And' {
            foreach ($operand in $Node.Operands) {
                if (-not (Test-DgRuleMatch -Node $operand -User $User -Context $Context -Item $Item)) { return $false }
            }
            return $true
        }
        'Or' {
            foreach ($operand in $Node.Operands) {
                if (Test-DgRuleMatch -Node $operand -User $User -Context $Context -Item $Item) { return $true }
            }
            return $false
        }
        'Not' {
            return -not (Test-DgRuleMatch -Node $Node.Operand -User $User -Context $Context -Item $Item)
        }
        'Collection' {
            # Assign first: Get-DgUserValue returns the collection as one object, and piping the
            # call directly would hand Where-Object the whole collection as a single item.
            $values = Get-DgUserValue -User $User -Entry $Node.Entry
            $items = @($values | Where-Object { $null -ne $_ })
            if ($Node.Quantifier -eq 'any') {
                foreach ($entry in $items) {
                    if (Test-DgRuleMatch -Node $Node.Condition -User $User -Context $Context -Item $entry) { return $true }
                }
                return $false
            }
            foreach ($entry in $items) {
                if (-not (Test-DgRuleMatch -Node $Node.Condition -User $User -Context $Context -Item $entry)) { return $false }
            }
            return $true
        }
        'MemberOf' {
            $userId = [string](Get-DgFieldValue -Object $User -Name 'id')
            foreach ($groupId in $Node.GroupIds) {
                if (-not $Context.GroupMembers.ContainsKey($groupId)) {
                    throw [System.InvalidOperationException]::new("members of group $groupId were not loaded")
                }
                if ($Context.GroupMembers[$groupId].Contains($userId)) { return $true }
            }
            return $false
        }
        'DirectReports' {
            $userId = [string](Get-DgFieldValue -Object $User -Name 'id')
            if ($userId -eq $Node.ManagerId) { return $true }
            $manager = Get-DgFieldValue -Object $User -Name 'manager'
            return ([string](Get-DgFieldValue -Object $manager -Name 'id')) -eq $Node.ManagerId
        }
        'Comparison' {
            $actual = if ($null -ne $Node.Entry) {
                Get-DgUserValue -User $User -Entry $Node.Entry
            } elseif ($Node.Item -eq '_') {
                $Item
            } else {
                Get-DgFieldValue -Object $Item -Name $Node.Item
            }
            return Test-DgComparison -Node $Node -Actual $actual -Context $Context
        }
    }
    throw [System.InvalidOperationException]::new("unknown compiled node kind $($Node.Kind)")
}
