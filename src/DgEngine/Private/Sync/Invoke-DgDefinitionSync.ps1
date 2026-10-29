function Invoke-DgDefinitionSync {
    <#
    .SYNOPSIS
        Syncs one due definition: resolves or creates its group, plans, writes, and stores the
        status document and (unless the run was quiet) a run record.
    .DESCRIPTION
        Never throws for problems of this definition: they end as LastResult = Error with the
        message, so the other definitions still sync. Steps:
        1. Target group: read it, or create it (target.mode = create, first real write). The new
           group's ID is stored in the status document at once, so a crash can't create it twice.
        2. Checks the plan doesn't cover: group type matches, a dynamic group is only taken over
           when the adoption converts it.
        3. Exchange groups: users without an Exchange recipient are skipped.
        4. Diff, compare group, Get-DgSyncPlan (all safety checks).
        5. Write: convert from dynamic, rename on adopt, marker on the first write, then adds and
           removes. A failed single add or remove makes the result Warning.
        6. Status document always; run record when something changed, warned, failed or ran dry.

        Context: Store, Provider, Mode, JobId, Now, AccessMode, Settings (ConvertTo-DgSetting),
        Graph (directory for users and compare groups), Target (directory of the group type),
        UsersById, Recipients (Exchange only).
    .EXAMPLE
        Invoke-DgDefinitionSync -Item $item -Evaluation $result -Context $context
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Item,

        [Parameter(Mandatory)]
        [pscustomobject] $Evaluation,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $startedAt = [DateTimeOffset]::UtcNow
    $settings = $Context.Settings
    $warnings = [System.Collections.Generic.List[string]]::new()
    $state = @{
        Result         = 'Error'
        Error          = $null
        GroupId        = $Item.GroupId
        Plan           = $null
        Desired        = $Evaluation.Desired
        DesiredIds     = $null
        Skipped        = [string[]]@()
        AddedIds       = [string[]]@()
        RemovedIds     = [string[]]@()
        Written        = $false
        Compare        = $null
        MemberCount    = $Item.Status.MemberCount
        WrittenHash    = $Item.Status.LastWrittenMembersHash
        UsedHash       = $Item.Status.UsedApprovalHash
        ManualReverted = @{ added = 0; removed = 0 }
    }

    $writeStatus = {
        param([bool] $Final, [string] $RunId)
        $plan = $state.Plan
        $counts = if ($state.Desired) { $state.Desired.Counts } else { $null }
        $pending = $null
        if ($plan -and $plan.PendingApproval) {
            $previous = $Item.Status.PendingApproval
            $detectedAt = if ($previous -and [string](Get-DgFieldValue -Object $previous -Name 'diffHash') -eq $plan.PendingApproval.diffHash) {
                ConvertFrom-DgTimestamp -Value (Get-DgFieldValue -Object $previous -Name 'detectedAt')
            } else { $null }
            if (-not $detectedAt) { $detectedAt = $Context.Now }
            $pending = [ordered]@{
                kind       = $plan.PendingApproval.kind
                diffHash   = $plan.PendingApproval.diffHash
                adds       = [int]$plan.PendingApproval.adds
                removes    = [int]$plan.PendingApproval.removes
                percent    = [double]$plan.PendingApproval.percent
                detectedAt = ConvertTo-DgTimestamp -Value $detectedAt
            }
        }
        $handled = if ($Item.SyncRequestAt) { $Item.SyncRequestAt } else { $Item.Status.HandledSyncRequestAt }
        $lastRunId = if ($RunId) { $RunId } elseif ($Item.Status.LastRunId) { $Item.Status.LastRunId } else { $null }
        $document = [ordered]@{
            id                     = "status-$($Item.Id)"
            pk                     = $Item.Id
            type                   = 'status'
            schemaVersion          = 1
            groupId                = $state.GroupId
            lastSyncUtc            = ConvertTo-DgTimestamp -Value $Context.Now
            lastResult             = if ($Final) { $state.Result } else { 'Error' }
            dryRunReason           = if ($plan -and $plan.DryRunReason) { $plan.DryRunReason } else { $null }
            memberCount            = [int]$state.MemberCount
            added                  = $state.AddedIds.Count
            removed                = $state.RemovedIds.Count
            skipped                = $state.Skipped.Count
            excluded               = [ordered]@{ disabled = if ($counts) { [int]$counts.Disabled } else { 0 }; guests = if ($counts) { [int]$counts.Guests } else { 0 } }
            warnings               = [string[]]@($warnings)
            lastError              = if ($state.Error) { ([string]$state.Error).Substring(0, [Math]::Min(2000, ([string]$state.Error).Length)) } else { $null }
            lastRunId              = $lastRunId
            handledSyncRequestAt   = if ($handled) { ConvertTo-DgTimestamp -Value $handled } else { $null }
            pendingApproval        = $pending
            usedApprovalHash       = if ($state.UsedHash) { $state.UsedHash } else { $null }
            lastWrittenMembersHash = if ($state.WrittenHash) { $state.WrittenHash } else { $null }
            compare                = if ($state.Compare) {
                [ordered]@{ groupId = $state.Compare.groupId; onlyInRdg = $state.Compare.onlyInRdgCount; onlyInCompare = $state.Compare.onlyInCompareCount }
            } else { $null }
        }
        if (-not $Final) {
            # Provisional write right after creating a group: only the group ID matters.
            $document.lastError = 'the run stopped right after creating the group'
        }
        [void](Set-DgStoreItem -Store $Context.Store -Container state -Document $document)
    }

    try {
        if ($Evaluation.Status -ne 'OK') { throw [System.InvalidOperationException]::new($Evaluation.Error) }
        $desiredIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($id in $Evaluation.Desired.MemberIds) { [void]$desiredIds.Add($id) }
        foreach ($warning in $Evaluation.Desired.Warnings) { if ($warning) { $warnings.Add($warning) } }

        $readOnly = $Context.AccessMode -eq 'read-only'
        $newGroupDryRun = $settings.NewGroupsDryRun -and -not $Item.HasStatus -and $Item.TargetMode -ne 'adopt'
        $firstFill = $false

        # 1. Target group
        $group = $null
        if ($Item.TargetMode -eq 'create' -and -not $state.GroupId) {
            $name = Get-DgGroupName -Name $Item.DisplayName -Prefix $settings.Prefix -Suffix $settings.Suffix
            if (-not $readOnly -and -not $Item.DryRun -and -not $newGroupDryRun) {
                $alias = if ($Item.MailNickname) { $Item.MailNickname } else { Get-DgMailNickname -Name $Item.DisplayName -Fallback ("rdg-" + $Item.Id.Substring(4)) }
                if (-not $PSCmdlet.ShouldProcess($name, 'Create group')) { throw [System.InvalidOperationException]::new('group creation was skipped (WhatIf)') }
                $group = New-DgDirectoryGroup -Directory $Context.Target -GroupType $Item.GroupType -DisplayName $name -MailNickname $alias -Confirm:$false
                $state.GroupId = $group.Id.ToLowerInvariant()
                & $writeStatus $false $null
                $firstFill = $true
            } else {
                # Would be created: plan against an empty group.
                $group = [pscustomobject]@{ Id = $null; DisplayName = $name; OnPremisesSynced = $false; IsAssignableToRole = $false; IsDynamic = $false; GroupTypes = @() }
            }
        } else {
            $group = Get-DgDirectoryGroup -Directory $Context.Target -GroupId $state.GroupId
            if (-not $group) { throw [System.InvalidOperationException]::new("the target group $($state.GroupId) doesn't exist (or isn't a $($Item.GroupType) group in $($Context.Provider))") }
            $firstFill = $Item.TargetMode -eq 'create' -and -not $Item.Status.LastWrittenMembersHash
        }

        # 2. Checks outside the plan
        $blocked = $null
        if ($Context.Target.Kind -eq 'Graph' -and $group.Id) {
            $unified = @($group.GroupTypes) -contains 'Unified'
            if ($Item.GroupType -eq 'Microsoft365' -and -not $unified) { $blocked = 'the group is not a Microsoft 365 group, but the definition says Microsoft365' }
            if ($Item.GroupType -eq 'Security' -and $unified) { $blocked = 'the group is a Microsoft 365 group, but the definition says Security' }
        }
        if (-not $blocked -and $group.IsDynamic -and -not ($Item.TargetMode -eq 'adopt' -and $Item.ConvertFromDynamic)) {
            $blocked = 'the group has dynamic membership; adopt it with "convert from dynamic" to let RDG manage it'
        }

        # 3. Exchange: only users with a recipient
        if ($Context.Provider -eq 'Exchange') {
            $skipped = [System.Collections.Generic.List[string]]::new()
            foreach ($id in @($desiredIds)) {
                if (-not $Context.Recipients -or -not $Context.Recipients.ContainsKey($id)) {
                    [void]$desiredIds.Remove($id)
                    $skipped.Add($id.ToLowerInvariant())
                }
            }
            $skipped.Sort([System.StringComparer]::Ordinal)
            $state.Skipped = $skipped.ToArray()
        }
        $state.DesiredIds = $desiredIds

        # 4. Diff, compare, plan
        $current = [object[]]@()
        if ($group.Id) { $current = Get-DgDirectoryMember -Directory $Context.Target -Group $group }
        $diff = Get-DgMemberDiff -DesiredIds $desiredIds -CurrentMembers $current
        if ($Item.CompareGroupId) {
            $compareMembers = Get-DgDirectoryUserMemberId -Directory $Context.Graph -GroupId $Item.CompareGroupId -Transitive $false
            if ($compareMembers.Found) {
                $state.Compare = Get-DgCompareResult -GroupId $Item.CompareGroupId -DesiredIds $desiredIds -CompareIds ([string[]]@($compareMembers.UserIds)) -Users $Context.Users
            } else {
                $warnings.Add("the compare group $($Item.CompareGroupId) doesn't exist")
            }
        }
        $desiredForPlan = [pscustomobject]@{ MemberIds = $desiredIds; Warnings = [string[]]@($warnings) }
        $planDefinition = @{
            ChangeLimitPercent = $Item.ChangeLimitPercent; AllowEmpty = $Item.AllowEmpty; DryRun = $Item.DryRun
            TargetMode = $Item.TargetMode; Adopted = $Item.Adopted; Approval = $Item.Approval
        }
        $planSettings = @{ ChangeLimitPercent = $settings.ChangeLimitPercent; ChangeLimitMinChanges = $settings.ChangeLimitMinChanges }
        $plan = Get-DgSyncPlan -Definition $planDefinition -Desired $desiredForPlan -Diff $diff -Group $group -Settings $planSettings `
            -Status $Item.Status -AccessMode $Context.AccessMode -FirstFill:$firstFill -NewGroupDryRun:$newGroupDryRun
        if ($blocked -and $plan.Result -ne 'Blocked') {
            $plan = [pscustomobject]@{
                PSTypeName = 'Dg.SyncPlan'; Result = 'Blocked'; Write = $false; DryRunReason = $null; Adds = $plan.Adds; Removes = $plan.Removes
                DiffHash = $plan.DiffHash; Percent = $plan.Percent; PendingApproval = $null; UseApprovalHash = $null; Block = $blocked
                ManualChangeDetected = $plan.ManualChangeDetected; Warnings = $plan.Warnings; Then = $null
            }
        }
        $state.Plan = $plan
        $warnings.Clear()
        foreach ($warning in $plan.Warnings) { $warnings.Add($warning) }
        $state.AddedIds = $plan.Adds
        $state.RemovedIds = $plan.Removes
        $state.MemberCount = $desiredIds.Count
        if ($plan.Result -eq 'Blocked') { $state.Error = $plan.Block }

        # 5. Write
        if ($plan.Write -and $PSCmdlet.ShouldProcess($group.DisplayName, 'Sync members')) {
            if ($group.IsDynamic) {
                ConvertTo-DgAssignedGroup -Directory $Context.Target -Group $group -Confirm:$false
            }
            if ($Item.TargetMode -eq 'adopt' -and $Item.RenameOnAdopt) {
                $base = if ($Item.DisplayName) { $Item.DisplayName } else { $group.DisplayName }
                $newName = Get-DgGroupName -Name $base -Prefix $settings.Prefix -Suffix $settings.Suffix
                if ($newName -cne $group.DisplayName) { Rename-DgDirectoryGroup -Directory $Context.Target -Group $group -DisplayName $newName -Confirm:$false }
            }
            if ($settings.MarkerEnabled -and -not $Item.Status.LastWrittenMembersHash) {
                Set-DgDirectoryMarker -Directory $Context.Target -Group $group -DefinitionId $Item.Id -Confirm:$false
            }
            $addResult = Add-DgDirectoryMember -Directory $Context.Target -Group $group -UserIds $plan.Adds -Confirm:$false
            $removeResult = Remove-DgDirectoryMember -Directory $Context.Target -Group $group -UserIds $plan.Removes -Confirm:$false
            foreach ($failure in @($addResult.Failed) + @($removeResult.Failed)) {
                if (-not $failure) { continue }
                $verb = if ($plan.Adds -contains $failure.Id) { 'add' } else { 'remove' }
                $user = $Context.UsersById[$failure.Id]
                $label = if ($user) { [string](Get-DgFieldValue -Object $user -Name 'userPrincipalName') } else { $failure.Id }
                $warnings.Add("could not $verb ${label}: $($failure.Error)")
            }
            $state.AddedIds = [string[]]@($addResult.Succeeded)
            $state.RemovedIds = [string[]]@($removeResult.Succeeded)
            $final = [System.Collections.Generic.HashSet[string]]::new($diff.CurrentUserIds, [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($id in $state.AddedIds) { [void]$final.Add($id) }
            foreach ($id in $state.RemovedIds) { [void]$final.Remove($id) }
            $state.MemberCount = $final.Count
            $state.WrittenHash = Get-DgMemberSetHash -Ids ([string[]]@($final))
            $state.Written = $true
            if ($plan.UseApprovalHash) { $state.UsedHash = $plan.UseApprovalHash }
            if ($plan.ManualChangeDetected) { $state.ManualReverted = @{ added = $state.AddedIds.Count; removed = $state.RemovedIds.Count } }
        }
        $state.Result = if ($plan.Result -eq 'OK' -and $warnings.Count) { 'Warning' } else { $plan.Result }
    } catch {
        $state.Result = 'Error'
        $state.Error = $_.Exception.Message
    }

    # 6. Run record and status
    $changed = $state.Written -and ($state.AddedIds.Count + $state.RemovedIds.Count) -gt 0
    $quiet = $state.Result -eq 'OK' -and -not $changed -and $warnings.Count -eq 0
    $runId = $null
    if (-not $quiet) {
        $runId = "run-$($Context.JobId.ToLowerInvariant())-$($Item.Id)"
        $plan = $state.Plan
        $counts = if ($state.Desired) { $state.Desired.Counts } else { $null }
        $approval = $null
        if ($plan -and $plan.PendingApproval) {
            $approval = [ordered]@{ kind = $plan.PendingApproval.kind; diffHash = $plan.PendingApproval.diffHash; adds = [int]$plan.PendingApproval.adds; removes = [int]$plan.PendingApproval.removes; percent = [double]$plan.PendingApproval.percent }
        } elseif ($state.Written -and $plan.UseApprovalHash -and $Item.Approval) {
            $approval = [ordered]@{
                kind = [string](Get-DgFieldValue -Object $Item.Approval -Name 'kind'); diffHash = $plan.UseApprovalHash
                adds = $plan.Adds.Count; removes = $plan.Removes.Count; percent = [double]$plan.Percent
            }
        }
        $errorText = if ($state.Error) { ([string]$state.Error).Substring(0, [Math]::Min(4000, ([string]$state.Error).Length)) } else { $null }
        $run = [ordered]@{
            id                    = $runId
            pk                    = $Item.Id
            type                  = 'run'
            schemaVersion         = 1
            jobId                 = $Context.JobId.ToLowerInvariant()
            runbook               = $Context.Provider
            mode                  = $Context.Mode
            startedAt             = ConvertTo-DgTimestamp -Value $startedAt
            durationMs            = [long]$clock.ElapsedMilliseconds
            engineVersion         = Get-DgEngineVersion
            definitionName        = $Item.Name
            groupId               = $state.GroupId
            result                = $state.Result
            dryRun                = $state.Result -in @('DryRun', 'WaitingForApproval')
            dryRunReason          = if ($plan -and $plan.DryRunReason) { $plan.DryRunReason } else { $null }
            then                  = Get-DgFieldValue -Object $plan -Name 'Then'
            addedCount            = $state.AddedIds.Count
            removedCount          = $state.RemovedIds.Count
            skippedCount          = $state.Skipped.Count
            added                 = ConvertTo-DgUserRef -Ids $state.AddedIds -UsersById $Context.UsersById
            removed               = ConvertTo-DgUserRef -Ids $state.RemovedIds -UsersById $Context.UsersById
            skipped               = ConvertTo-DgUserRef -Ids $state.Skipped -UsersById $Context.UsersById
            excluded              = [ordered]@{ disabled = if ($counts) { [int]$counts.Disabled } else { 0 }; guests = if ($counts) { [int]$counts.Guests } else { 0 } }
            manualChangesReverted = [ordered]@{ added = [int]$state.ManualReverted.added; removed = [int]$state.ManualReverted.removed }
            approval              = $approval
            warnings              = [string[]]@($warnings | ForEach-Object { if ($_.Length -gt 1000) { $_.Substring(0, 1000) } else { $_ } })
            error                 = $errorText
            compare               = $state.Compare
        }
        try {
            [void](Set-DgStoreItem -Store $Context.Store -Container runs -Document $run)
        } catch {
            $warnings.Add("the run record could not be written: $($_.Exception.Message)")
            $runId = $null
        }
    }
    & $writeStatus $true $runId

    [pscustomobject]@{
        PSTypeName   = 'Dg.DefinitionSyncResult'
        DefinitionId = $Item.Id
        Name         = $Item.Name
        Result       = $state.Result
        Error        = $state.Error
        Added        = $state.AddedIds.Count
        Removed      = $state.RemovedIds.Count
        Skipped      = @($state.Skipped).Count
        MemberCount  = $state.MemberCount
        DryRunReason = if ($state.Plan) { $state.Plan.DryRunReason } else { $null }
        Then         = Get-DgFieldValue -Object $state.Plan -Name 'Then'
        Written      = $state.Written
        RunId        = $runId
        Warnings     = [string[]]@($warnings)
        DurationMs   = [long]$clock.ElapsedMilliseconds
    }
}
