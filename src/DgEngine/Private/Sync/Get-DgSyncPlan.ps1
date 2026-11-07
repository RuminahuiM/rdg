function Get-DgSyncPlan {
    <#
    .SYNOPSIS
        Decides what the engine does for one definition: write the diff, run dry, wait for
        approval, or block. Pure logic, no directory calls.
    .DESCRIPTION
        Checks, in this order (first match wins):
        1. Source: the group is synced from on-prem AD or is role-assignable -> Blocked.
        2. Read-only installation -> DryRun (readOnly).
        3. Adoption not yet approved -> WaitingForApproval with a pending "adopt" approval.
           Once approved, the adoption approval covers the first write if its hash still matches.
        4. Definition dry run -> DryRun (definition); then a definition's very first run when
           the setting "new groups start in dry run" is on -> DryRun (newGroup).
        5. Empty result while the group has user members and AllowEmpty is off -> Blocked.
        6. Change limit: adds + removes > limit % of current user members, from MinChanges up.
           Not applied on the first fill of a group the engine created, or when an approval
           with the same diff hash exists and hasn't been used. Otherwise Blocked with a
           pending "changeLimit" approval.
        Otherwise OK (Warning if the desired-members step reported warnings or a manual change
        was detected).
        A dry run (steps 2 and 4) also carries Then: result, message and approvalKind of the same
        checks with read-write access and dry run off, so a dry run shows what a real run would do.

        Definition: hashtable with ChangeLimitPercent (null = organisation default), AllowEmpty,
        DryRun, TargetMode, Adopted, Approval (kind, diffHash). Status: previous status document
        fields UsedApprovalHash, LastWrittenMembersHash. Settings: ChangeLimitPercent,
        ChangeLimitMinChanges. Group: OnPremisesSynced, IsAssignableToRole.
    .EXAMPLE
        Get-DgSyncPlan -Definition $def -Desired $desired -Diff $diff -Group $group -Settings $settings
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Definition,

        [Parameter(Mandatory)]
        [pscustomobject] $Desired,

        [Parameter(Mandatory)]
        [pscustomobject] $Diff,

        [Parameter(Mandatory)]
        [object] $Group,

        [Parameter(Mandatory)]
        [object] $Settings,

        [AllowNull()]
        [object] $Status,

        [ValidateSet('read-only', 'read-write')]
        [string] $AccessMode = 'read-write',

        # The engine created the group in this run or the previous one and never filled it.
        [switch] $FirstFill,

        # First run of a new definition while the setting "new groups start in dry run" is on.
        [switch] $NewGroupDryRun
    )

    $get = { param($object, $name) Get-DgFieldValue -Object $object -Name $name }
    $adds = $Diff.Adds
    $removes = $Diff.Removes
    $changes = $adds.Count + $removes.Count
    $diffHash = Get-DgDiffHash -Adds $adds -Removes $removes
    $base = [Math]::Max($Diff.CurrentUserCount, 1)
    $percent = [Math]::Round(100.0 * $changes / $base, 1)
    $approval = & $get $Definition 'Approval'
    $usedHash = [string](& $get $Status 'UsedApprovalHash')
    $approvalMatches = $approval -and [string](& $get $approval 'diffHash') -eq $diffHash -and $usedHash -ne $diffHash
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($warning in @($Desired.Warnings)) { if ($warning) { $warnings.Add($warning) } }

    # Manual change: the group differs from what the engine wrote last time.
    $lastWritten = [string](& $get $Status 'LastWrittenMembersHash')
    $currentHash = Get-DgMemberSetHash -Ids ([string[]]@($Diff.CurrentUserIds))
    $manualChange = [bool]$lastWritten -and $lastWritten -ne $currentHash
    if ($manualChange -and $changes -gt 0) {
        $warnings.Add("manual change detected: $($adds.Count) to add, $($removes.Count) to remove, reverted")
    }

    $plan = [ordered]@{
        PSTypeName           = 'Dg.SyncPlan'
        Result               = 'OK'
        Write                = $true
        DryRunReason         = $null
        Adds                 = $adds
        Removes              = $removes
        DiffHash             = $diffHash
        Percent              = $percent
        PendingApproval      = $null
        UseApprovalHash      = $null
        Block                = $null
        ManualChangeDetected = $manualChange
        Warnings             = $warnings
        Then                 = $null
    }
    $finish = {
        param([string] $Result, [bool] $Write, [string] $Reason, [string] $Message)
        $plan.Result = $Result
        $plan.Write = $Write
        $plan.DryRunReason = if ($Reason) { $Reason } else { $null }
        if ($Message) { $plan.Block = $Message }
        if ($plan.Result -eq 'OK' -and $plan.Warnings.Count) { $plan.Result = 'Warning' }
        $plan.Warnings = $plan.Warnings.ToArray()
        [pscustomobject]$plan
    }
    $pending = {
        param([string] $Kind)
        [pscustomobject]@{ kind = $Kind; diffHash = $diffHash; adds = $adds.Count; removes = $removes.Count; percent = $percent }
    }

    # 1. Source
    if (& $get $Group 'OnPremisesSynced') {
        return & $finish 'Blocked' $false $null 'the group is synced from on-premises AD; RDG cannot manage it'
    }
    if (& $get $Group 'IsAssignableToRole') {
        return & $finish 'Blocked' $false $null 'the group is role-assignable; RDG does not manage those'
    }

    # What a run would do without the dry-run reasons (read-only, definition dry run, new group):
    # the same checks with read-write access and dry run off. Recorded on dry runs as "Then".
    $then = {
        $writable = @{}
        foreach ($key in @('ChangeLimitPercent', 'AllowEmpty', 'TargetMode', 'Adopted', 'Approval')) { $writable[$key] = & $get $Definition $key }
        $writable.DryRun = $false
        $real = Get-DgSyncPlan -Definition $writable -Desired $Desired -Diff $Diff -Group $Group -Settings $Settings -Status $Status `
            -AccessMode 'read-write' -FirstFill:$FirstFill
        $message = if ($real.Block) { $real.Block } elseif ($real.Result -eq 'WaitingForApproval') { "the adoption needs an approval first ($changes changes, $percent % of $($Diff.CurrentUserCount) members)" } else { $null }
        [ordered]@{
            result       = $real.Result
            message      = $message
            approvalKind = if ($real.PendingApproval) { $real.PendingApproval.kind } else { $null }
        }
    }

    # 2. Read-only installation
    if ($AccessMode -eq 'read-only') {
        $plan.Then = & $then
        return & $finish 'DryRun' $false 'readOnly' $null
    }

    # 3. Adoption
    $isAdoption = (& $get $Definition 'TargetMode') -eq 'adopt'
    if ($isAdoption -and -not (& $get $Definition 'Adopted')) {
        $plan.PendingApproval = & $pending 'adopt'
        return & $finish 'WaitingForApproval' $false 'adoption' $null
    }

    # 4. Definition dry run
    if (& $get $Definition 'DryRun') {
        $plan.Then = & $then
        return & $finish 'DryRun' $false 'definition' $null
    }
    if ($NewGroupDryRun) {
        $plan.Then = & $then
        return & $finish 'DryRun' $false 'newGroup' $null
    }

    if ($changes -eq 0) {
        return & $finish 'OK' $true $null $null
    }

    # 5. Empty result
    if ($Desired.MemberIds.Count -eq 0 -and $Diff.CurrentUserCount -gt 0 -and -not (& $get $Definition 'AllowEmpty')) {
        return & $finish 'Blocked' $false $null "the rule matches nobody and would empty the group ($($Diff.CurrentUserCount) members); allow an empty result on the definition if that is intended"
    }

    # 6. Change limit
    $limit = & $get $Definition 'ChangeLimitPercent'
    if ($null -eq $limit) { $limit = & $get $Settings 'ChangeLimitPercent' }
    $minChanges = & $get $Settings 'ChangeLimitMinChanges'
    if ($null -eq $minChanges) { $minChanges = 10 }
    $overLimit = $changes -ge $minChanges -and $percent -gt [double]$limit
    if ($overLimit -and -not $FirstFill) {
        $approvalKind = if ($approval) { [string](& $get $approval 'kind') } else { '' }
        if ($approvalMatches -and $approvalKind -in @('changeLimit', 'adopt')) {
            $plan.UseApprovalHash = $diffHash
        } else {
            $plan.PendingApproval = & $pending 'changeLimit'
            return & $finish 'Blocked' $false $null "$changes changes are $percent % of $($Diff.CurrentUserCount) members, above the limit of $limit %; approve the change or adjust the rule"
        }
    }
    if ($isAdoption -and $approvalMatches) {
        $plan.UseApprovalHash = $diffHash
    }

    & $finish 'OK' $true $null $null
}
