function ConvertTo-DgWorkItem {
    <#
    .SYNOPSIS
        Combines a definition document and its status document into the work item the engine
        uses during a run (PascalCase fields, dates parsed, group ID resolved).
    .DESCRIPTION
        GroupId is the target group: target.groupId for existing and adopted groups, or the
        status document's groupId for a group the engine created.
    .EXAMPLE
        ConvertTo-DgWorkItem -Definition $definitionDocument -Status $statusDocument
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Definition,

        [AllowNull()]
        [System.Collections.IDictionary] $Status
    )

    $get = { param($object, [string] $name) if ($object) { Get-DgFieldValue -Object $object -Name $name } else { $null } }
    $ids = {
        param($value)
        [string[]]@(@($value) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
    }
    $target = & $get $Definition 'target'
    $mode = [string](& $get $target 'mode')
    $groupId = if ($mode -eq 'create') { [string](& $get $Status 'groupId') } else { [string](& $get $target 'groupId') }
    $syncRequest = & $get $Definition 'syncRequest'
    $groupType = [string](& $get $Definition 'groupType')
    $limit = & $get $Definition 'changeLimitPercent'

    [pscustomobject]@{
        PSTypeName         = 'Dg.WorkItem'
        Id                 = [string](& $get $Definition 'id')
        Name               = [string](& $get $Definition 'name')
        GroupType          = $groupType
        Provider           = Get-DgProvider -GroupType $groupType
        TargetMode         = $mode
        GroupId            = if ($groupId) { $groupId.ToLowerInvariant() } else { $null }
        DisplayName        = [string](& $get $target 'displayName')
        MailNickname       = [string](& $get $target 'mailNickname')
        Adopted            = [bool](& $get $target 'adopted')
        RenameOnAdopt      = [bool](& $get $target 'renameOnAdopt')
        ConvertFromDynamic = [bool](& $get $target 'convertFromDynamic')
        Rule               = [string](& $get $Definition 'rule')
        IncludeUserIds     = & $ids (& $get $Definition 'includeUserIds')
        ExcludeUserIds     = & $ids (& $get $Definition 'excludeUserIds')
        IncludeDisabled    = [bool](& $get $Definition 'includeDisabled')
        IncludeGuests      = [bool](& $get $Definition 'includeGuests')
        FrequencyMinutes   = [int](& $get $Definition 'frequencyMinutes')
        Enabled            = [bool](& $get $Definition 'enabled')
        DryRun             = [bool](& $get $Definition 'dryRun')
        ChangeLimitPercent = if ($null -eq $limit) { $null } else { [int]$limit }
        AllowEmpty         = [bool](& $get $Definition 'allowEmpty')
        CompareGroupId     = [string](& $get $Definition 'compareGroupId')
        SyncRequestAt      = ConvertFrom-DgTimestamp -Value (& $get $syncRequest 'at')
        Approval           = & $get $Definition 'approval'
        HasStatus          = $null -ne $Status
        LastSyncUtc        = ConvertFrom-DgTimestamp -Value (& $get $Status 'lastSyncUtc')
        Status             = [pscustomobject]@{
            UsedApprovalHash       = [string](& $get $Status 'usedApprovalHash')
            LastWrittenMembersHash = [string](& $get $Status 'lastWrittenMembersHash')
            HandledSyncRequestAt   = ConvertFrom-DgTimestamp -Value (& $get $Status 'handledSyncRequestAt')
            LastRunId              = [string](& $get $Status 'lastRunId')
            MemberCount            = [int](& $get $Status 'memberCount')
            PendingApproval        = & $get $Status 'pendingApproval'
        }
    }
}
