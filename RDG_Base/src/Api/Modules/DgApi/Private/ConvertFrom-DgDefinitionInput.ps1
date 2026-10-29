function ConvertFrom-DgDefinitionInput {
    <#
    .SYNOPSIS
        Checks a DefinitionInput beyond the schema and returns the definition fields to store.
    .DESCRIPTION
        - The rule must be valid (engine validator); errors carry positions. 400.
        - memberOf groups must exist (RDG-managed or in Graph). 400.
        - create: no group ID. existing and adopt: the group must exist, match the group type,
          not be synced from on-prem AD, not be role-assignable (400), and not be managed by
          another definition (409). A Microsoft dynamic group can only be adopted; the API then
          sets convertFromDynamic.
        - The compare group must exist. 400.
        - adopted and convertFromDynamic are set by the API, never taken from the request; an
          adoption keeps "adopted" only while the target group stays the same.
        Defaults from the contract fill the optional fields.
    .EXAMPLE
        $fields = ConvertFrom-DgDefinitionInput -Context $Context -Body $body -Data $data
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context,

        [Parameter(Mandatory)]
        [hashtable] $Body,

        [Parameter(Mandatory)]
        [pscustomobject] $Data,

        # The stored definition when updating (excluded from the group-link check).
        [System.Collections.IDictionary] $Current
    )

    $value = { param([string] $Name, $Default) if ($Body.ContainsKey($Name)) { $Body[$Name] } else { $Default } }
    $errors = [System.Collections.Generic.List[object]]::new()

    # Rule
    $rule = [string]$Body['rule']
    $check = Test-DgRule -Rule $rule
    foreach ($ruleError in (Get-DgRuleErrorList -Check $check)) {
        $errors.Add([ordered]@{ field = 'rule'; message = $ruleError.message; position = $ruleError.position; line = $ruleError.line; column = $ruleError.column })
    }
    if ($check.Valid) {
        foreach ($unknown in @(Get-DgUnknownGroupId -Context $Context -GroupIds ([string[]]@($check.ReferencedGroupIds)) -Data $Data)) {
            $position = $rule.IndexOf($unknown, [System.StringComparison]::OrdinalIgnoreCase)
            $errors.Add([ordered]@{ field = 'rule'; message = "the memberOf group $unknown doesn't exist"; position = [Math]::Max($position, 0) })
        }
    }

    # Target
    $requested = $Body['target']
    $mode = [string]$requested['mode']
    $target = [ordered]@{ mode = $mode }
    $groupType = [string]$Body['groupType']
    $graph = $null
    if ($mode -eq 'create') {
        if ($requested['groupId']) { $errors.Add([ordered]@{ field = 'target.groupId'; message = 'a group RDG creates has no group ID yet; leave it out' }) }
        $target.displayName = [string]$requested['displayName']
        if ($requested['mailNickname']) { $target.mailNickname = [string]$requested['mailNickname'] }
    } else {
        $groupId = ([string]$requested['groupId']).ToLowerInvariant()
        $target.groupId = $groupId
        if ($requested['displayName']) { $target.displayName = [string]$requested['displayName'] }
        if ($requested['mailNickname']) { $target.mailNickname = [string]$requested['mailNickname'] }
        $graph = Get-DgApiGraph -Context $Context
        $group = Invoke-DgEngine -Name Get-DgDirectoryGroup -Parameters @{ Directory = $graph; GroupId = $groupId }
        if (-not $group) {
            $errors.Add([ordered]@{ field = 'target.groupId'; message = "the group $groupId doesn't exist" })
        } else {
            if ($group.OnPremisesSynced) { $errors.Add([ordered]@{ field = 'target.groupId'; message = 'the group is synced from on-premises AD; RDG cannot manage it' }) }
            if ($group.IsAssignableToRole) { $errors.Add([ordered]@{ field = 'target.groupId'; message = 'the group is role-assignable; RDG does not manage those' }) }
            if ($group.PSObject.Properties['GroupType'] -and $group.GroupType -ne $groupType) {
                $errors.Add([ordered]@{ field = 'groupType'; message = "the group is a $($group.GroupType) group, not $groupType" })
            }
            if ($group.IsDynamic -and $mode -ne 'adopt') {
                $errors.Add([ordered]@{ field = 'target.mode'; message = 'the group has dynamic membership; adopt it to let RDG take it over' })
            }
            if ($mode -eq 'adopt') {
                $target.renameOnAdopt = [bool]$requested['renameOnAdopt']
                $target.convertFromDynamic = [bool]$group.IsDynamic
                $previous = if ($Current) { $Current['target'] } else { $null }
                $sameGroup = $previous -and $previous['mode'] -eq 'adopt' -and ([string]$previous['groupId']).ToLowerInvariant() -eq $groupId
                $target.adopted = [bool]($sameGroup -and $previous['adopted'])
            }
            foreach ($other in $Data.Definitions) {
                if ($Current -and $other['id'] -eq $Current['id']) { continue }
                $linked = Get-DgDefinitionGroupId -Definition $other -Status $Data.Statuses[[string]$other['id']]
                if ($linked -eq $groupId) {
                    Stop-DgApi -Status 409 -Title 'Group already managed' -Detail "the group is already managed by the definition ""$($other['name'])"" ($($other['id']))"
                }
            }
        }
    }

    # Compare group
    $compareGroupId = & $value 'compareGroupId' $null
    if ($compareGroupId) {
        $compareGroupId = ([string]$compareGroupId).ToLowerInvariant()
        if (-not $graph) { $graph = Get-DgApiGraph -Context $Context }
        if (-not (Invoke-DgEngine -Name Get-DgDirectoryGroup -Parameters @{ Directory = $graph; GroupId = $compareGroupId })) {
            $errors.Add([ordered]@{ field = 'compareGroupId'; message = "the group $compareGroupId doesn't exist" })
        }
    }

    if ($errors.Count) {
        $title = if (@($errors | Where-Object { $_.field -eq 'rule' }).Count) { 'Rule is not valid' } else { 'Definition is not valid' }
        Stop-DgApi -Status 400 -Title $title -Type 'validation' -Extra @{ errors = $errors.ToArray() }
    }

    [ordered]@{
        name               = [string]$Body['name']
        groupType          = $groupType
        target             = $target
        rule               = $rule
        includeUserIds     = [string[]]@(@($Body['includeUserIds']) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
        excludeUserIds     = [string[]]@(@($Body['excludeUserIds']) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
        includeDisabled    = [bool](& $value 'includeDisabled' $false)
        includeGuests      = [bool](& $value 'includeGuests' $false)
        frequencyMinutes   = [int](& $value 'frequencyMinutes' 15)
        enabled            = [bool](& $value 'enabled' $true)
        dryRun             = [bool](& $value 'dryRun' $false)
        changeLimitPercent = $(if ($null -ne (& $value 'changeLimitPercent' $null)) { [int]$Body['changeLimitPercent'] } else { $null })
        allowEmpty         = [bool](& $value 'allowEmpty' $false)
        compareGroupId     = $compareGroupId
    }
}
