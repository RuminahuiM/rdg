function Get-DgPreview {
    <#
    .SYNOPSIS
        Shows what a definition would do now: its members, who is excluded and why, the diff to
        the current target group, the change-limit verdict and the compare lists.
    .DESCRIPTION
        Uses the same evaluation as the sync (memberOf, implicit filters, includes, excludes), so
        preview and sync never disagree. Reads Graph only. For Exchange group types, users without
        a mail address are flagged as "noExchangeRecipient"; the exact check happens at sync.
        Definition: a saved or unsaved definition document (the API gives an unsaved one a
        temporary ID). Definitions/Statuses: all stored documents, for memberOf references.
        Returns the PreviewResult of the API contract (ordered dictionary, camelCase).
        A definition that can't be evaluated (rule error, missing memberOf group) throws.
    .EXAMPLE
        Get-DgPreview -Definition $definition -Definitions $all -Statuses $statuses -Settings $settings -Graph $graph
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Definition,

        [AllowNull()]
        [System.Collections.IDictionary] $Status,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Definitions,

        [Parameter(Mandatory)]
        [hashtable] $Statuses,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Settings,

        [Parameter(Mandatory)]
        [hashtable] $Graph,

        # User snapshot to reuse (the API caches it for a few minutes); read from Graph if not given.
        [object[]] $Users,

        [Nullable[DateTimeOffset]] $Now
    )

    $at = if ($null -ne $Now) { [DateTimeOffset]$Now } else { [DateTimeOffset]::UtcNow }
    $options = ConvertTo-DgSetting -Document $Settings
    $item = ConvertTo-DgWorkItem -Definition $Definition -Status $Status
    $excludeIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($item.ExcludeUserIds), [System.StringComparer]::OrdinalIgnoreCase)
    # Evaluate without the exclude list, so the preview can name who it removes.
    $evaluated = $item.PSObject.Copy()
    $evaluated.ExcludeUserIds = [string[]]@()

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($document in $Definitions) {
        if ([string]$document['id'] -eq $item.Id) { continue }
        $items.Add((ConvertTo-DgWorkItem -Definition $document -Status $Statuses[[string]$document['id']]))
    }
    $items.Add($evaluated)

    if ($null -eq $Users) {
        $fields = Get-DgSnapshotField -Rules ([string[]]@($items | ForEach-Object { $_.Rule }))
        $Users = Get-DgDirectoryUser -Directory $Graph -Select (@($fields.Select) + @('mail')) -ExpandManager:$fields.ExpandManager
    }
    $usersById = @{}
    foreach ($user in $Users) { $usersById[[string](Get-DgFieldValue -Object $user -Name 'id')] = $user }

    $previewGraph = $Graph
    $provider = {
        param([string] $GroupId, [bool] $Transitive)
        Get-DgDirectoryUserMemberId -Directory $previewGraph -GroupId $GroupId -Transitive $Transitive
    }
    $results = @(Invoke-DgDefinitionEvaluation -Definitions $items.ToArray() -TargetIds @($item.Id) -Users $Users -Now $at `
            -NestedMembers $options.NestedMembers -GroupMemberProvider $provider)
    $result = $results | Where-Object { $_.DefinitionId -eq $item.Id } | Select-Object -First 1
    if (-not $result -or $result.Status -ne 'OK') {
        $reason = if ($result) { $result.Error } else { 'the definition was not evaluated' }
        throw [System.InvalidOperationException]::new($reason)
    }

    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($warning in $result.Desired.Warnings) { if ($warning) { $warnings.Add($warning) } }
    $excluded = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $result.Desired.Excluded) {
        $excluded.Add(@{ Id = [string](Get-DgFieldValue -Object $entry.User -Name 'id'); Reason = $entry.Reason })
    }
    $isExchange = $item.Provider -eq 'Exchange'
    $memberIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $members = [System.Collections.Generic.List[string]]::new()
    $noMail = 0
    foreach ($user in $result.Desired.Members) {
        $id = [string](Get-DgFieldValue -Object $user -Name 'id')
        if ($excludeIds.Contains($id)) { $excluded.Add(@{ Id = $id; Reason = 'excludeList' }); continue }
        if ($isExchange -and -not [string](Get-DgFieldValue -Object $user -Name 'mail')) {
            $excluded.Add(@{ Id = $id; Reason = 'noExchangeRecipient' })
            $noMail++
            continue
        }
        if ($memberIds.Add($id)) { $members.Add($id) }
    }
    if ($noMail) { $warnings.Add("$noMail users have no mail address and probably no Exchange recipient; the sync skips users without one") }

    $sortByUpn = {
        param([string[]] $Ids)
        [string[]]@($Ids | Sort-Object -Property { [string](Get-DgFieldValue -Object $usersById[$_] -Name 'userPrincipalName') }, { $_ })
    }

    # Diff against the current target group
    $diff = $null
    $limit = if ($null -ne $item.ChangeLimitPercent) { [int]$item.ChangeLimitPercent } else { $options.ChangeLimitPercent }
    $changeLimit = [ordered]@{ wouldBlock = $false; percent = 0.0; limitPercent = $limit }
    $emptyResult = [ordered]@{ wouldBlock = $false; currentMembers = 0; allowEmpty = [bool]$item.AllowEmpty }
    if ($item.GroupId) {
        $group = Get-DgDirectoryGroup -Directory $Graph -GroupId $item.GroupId
        if ($group) {
            $current = Get-DgDirectoryMember -Directory $Graph -Group $group
            $memberDiff = Get-DgMemberDiff -DesiredIds $memberIds -CurrentMembers $current
            $adds = [string[]]@(& $sortByUpn $memberDiff.Adds)
            $removes = [string[]]@(& $sortByUpn $memberDiff.Removes)
            $diff = [ordered]@{
                addCount    = $adds.Count
                removeCount = $removes.Count
                adds        = ConvertTo-DgUserRef -Ids $adds -UsersById $usersById -Limit 200
                removes     = ConvertTo-DgUserRef -Ids $removes -UsersById $usersById -Limit 200
            }
            $changes = $adds.Count + $removes.Count
            $percent = [Math]::Round(100.0 * $changes / [Math]::Max($memberDiff.CurrentUserCount, 1), 1)
            $changeLimit.percent = [double]$percent
            $changeLimit.wouldBlock = $changes -ge $options.ChangeLimitMinChanges -and $percent -gt $limit
            # Same rule as the sync plan: a result that would empty a group with members is blocked
            # unless the definition allows an empty result.
            $emptyResult.currentMembers = [int]$memberDiff.CurrentUserCount
            $emptyResult.wouldBlock = $memberIds.Count -eq 0 -and $memberDiff.CurrentUserCount -gt 0 -and -not $item.AllowEmpty
        } else {
            $warnings.Add("the target group $($item.GroupId) doesn't exist")
        }
    }

    $compare = $null
    if ($item.CompareGroupId) {
        $compareMembers = Get-DgDirectoryUserMemberId -Directory $Graph -GroupId $item.CompareGroupId -Transitive $false
        if ($compareMembers.Found) {
            $compareSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($compareMembers.UserIds), [System.StringComparer]::OrdinalIgnoreCase)
            $onlyInRdg = [string[]]@(& $sortByUpn @($members | Where-Object { -not $compareSet.Contains($_) }))
            $onlyInCompare = [string[]]@(& $sortByUpn @($compareSet | Where-Object { -not $memberIds.Contains($_) }))
            $compare = [ordered]@{
                onlyInRdgCount     = $onlyInRdg.Count
                onlyInCompareCount = $onlyInCompare.Count
                onlyInRdg          = ConvertTo-DgUserRef -Ids $onlyInRdg -UsersById $usersById -Limit 200
                onlyInCompare      = ConvertTo-DgUserRef -Ids $onlyInCompare -UsersById $usersById -Limit 200
            }
        } else {
            $warnings.Add("the compare group $($item.CompareGroupId) doesn't exist")
        }
    }

    $sortedMembers = [string[]]@(& $sortByUpn $members.ToArray())
    # Complete counts per reason; the list itself stops at 200 entries.
    $excludedCounts = [ordered]@{ disabled = 0; guest = 0; excludeList = 0; noExchangeRecipient = 0 }
    foreach ($entry in $excluded) { if ($excludedCounts.Contains([string]$entry.Reason)) { $excludedCounts[[string]$entry.Reason]++ } }
    $excludedRefs = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in ($excluded | Select-Object -First 200)) {
        $excludedRefs.Add([ordered]@{ user = (ConvertTo-DgUserRef -Ids @($entry.Id) -UsersById $usersById)[0]; reason = $entry.Reason })
    }

    [ordered]@{
        memberCount    = $sortedMembers.Count
        members        = ConvertTo-DgUserRef -Ids $sortedMembers -UsersById $usersById -Limit 200
        excluded       = $excludedRefs.ToArray()
        excludedCounts = $excludedCounts
        diff           = $diff
        changeLimit    = $changeLimit
        emptyResult    = $emptyResult
        compare        = $compare
        warnings       = $warnings.ToArray()
    }
}
