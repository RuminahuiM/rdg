function Get-DgDesiredMember {
    <#
    .SYNOPSIS
        Computes the users one definition should have.
    .DESCRIPTION
        In this order: rule result, minus implicit filters (disabled, guests), plus the
        always-include list (bypasses the filters), minus the always-exclude list (always wins).
        Members are the user records; MemberIds is a case-insensitive set of their IDs. An
        always-include user who doesn't exist gives a warning, not an error.
    .EXAMPLE
        Get-DgDesiredMember -Compiled $compiled -Definition $definition -Users $users -Context $context
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Compiled,

        [Parameter(Mandatory)]
        [object] $Definition,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Users,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $matched = Invoke-DgRuleEvaluation -Compiled $Compiled -Users $Users -Context $Context
    $filtered = Select-DgImplicitFilter -Users $matched `
        -IncludeDisabled:([bool](Get-DgFieldValue -Object $Definition -Name 'IncludeDisabled')) `
        -IncludeGuests:([bool](Get-DgFieldValue -Object $Definition -Name 'IncludeGuests'))

    $members = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($user in $filtered.Kept) {
        if ($ids.Add([string](Get-DgFieldValue -Object $user -Name 'id'))) { $members.Add($user) }
    }

    # Includes bypass the filters: an explicit include is a deliberate choice.
    # Assign first, then wrap: Get-DgFieldValue returns a list as one object.
    $includeValue = Get-DgFieldValue -Object $Definition -Name 'IncludeUserIds'
    $includeIds = @(@($includeValue) | Where-Object { $_ })
    if ($includeIds) {
        $usersById = @{}
        foreach ($user in $Users) { $usersById[[string](Get-DgFieldValue -Object $user -Name 'id')] = $user }
        foreach ($includeId in $includeIds) {
            if (-not $usersById.ContainsKey([string]$includeId)) {
                $warnings.Add("always-include user $includeId was not found")
                continue
            }
            if ($ids.Add([string]$includeId)) { $members.Add($usersById[[string]$includeId]) }
        }
    }

    # Excludes always win.
    $excludeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $excludeValue = Get-DgFieldValue -Object $Definition -Name 'ExcludeUserIds'
    foreach ($excludeId in @($excludeValue)) {
        if ($excludeId) { [void]$excludeIds.Add([string]$excludeId) }
    }
    if ($excludeIds.Count) {
        $kept = [System.Collections.Generic.List[object]]::new()
        foreach ($user in $members) {
            $userId = [string](Get-DgFieldValue -Object $user -Name 'id')
            if ($excludeIds.Contains($userId)) { [void]$ids.Remove($userId) } else { $kept.Add($user) }
        }
        $members = $kept
    }

    [pscustomobject]@{
        PSTypeName = 'Dg.DesiredMembers'
        Members    = $members.ToArray()
        MemberIds  = $ids
        Excluded   = $filtered.Excluded
        Counts     = $filtered.Counts
        Warnings   = $warnings.ToArray()
    }
}
