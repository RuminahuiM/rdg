function Invoke-DgSync {
    <#
    .SYNOPSIS
        One engine run for one runbook: syncs every due definition of its group types.
    .DESCRIPTION
        Order of a run:
        1. Connect (from -Config) unless store and directories are passed in.
        2. Take the run lock (lease 2 x tick, renewed during long runs). If another job holds it:
           a scheduled run records a skipped tick; a SyncNow run waits up to 2 minutes, then
           defers (the request stays on the definition for the next scheduled run).
        3. Read settings. Paused: Paused record, heartbeat, done. Verbose logging on: verbose output.
        4. Read definitions and status documents; pick the due ones. Nothing due: heartbeat, done.
        5. Read all users once; check snapshot health. Unhealthy: nothing is written, the run fails.
        6. Evaluate the due definitions plus everything they reference (memberOf).
        7. Sync each due definition; one failing doesn't stop the others. After MaxRunTime
           the run stops and leaves the rest for the next tick.
        8. Heartbeat, release the lock.
        Result: Failed when any definition ended Blocked or Error, the snapshot was unhealthy or
        the time limit was hit; otherwise Succeeded, Paused, SkippedTick or Deferred.
        FailedDefinitions lists "name (reason)" for the job's error message.

        Config (from the runbook's Automation variables): ClientId, TenantDomain, CosmosEndpoint,
        CosmosDatabase, TickMinutes, AccessMode (read-only unless 'read-write'), MarkerExtension.
    .EXAMPLE
        Invoke-DgSync -Provider Entra -Mode Scheduled -Config $config
    .EXAMPLE
        Invoke-DgSync -Provider Exchange -Mode SyncNow -DefinitionId 'def-01JABCDEFGHJKMNPQRSTVWXYZ0' -Config $config
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Entra', 'Exchange')]
        [string] $Provider,

        [ValidateSet('Scheduled', 'SyncNow')]
        [string] $Mode = 'Scheduled',

        [AllowEmptyString()]
        [ValidatePattern('^(def-[0-9A-HJKMNP-TV-Z]{26})?$')]
        [string] $DefinitionId,

        [hashtable] $Config,

        [hashtable] $Store,

        [hashtable] $GraphDirectory,

        [hashtable] $ExchangeDirectory,

        [ValidateSet('read-only', 'read-write')]
        [string] $AccessMode,

        [ValidateRange(1, 60)]
        [int] $TickMinutes,

        [string] $JobId,

        [Nullable[DateTimeOffset]] $Now,

        # Azure stops cloud jobs after 3 hours; the engine stops itself before that.
        [TimeSpan] $MaxRunTime = [TimeSpan]::FromMinutes(150),

        [scriptblock] $Sleep = { param([double] $Seconds) Start-Sleep -Milliseconds ([int]($Seconds * 1000)) }
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    Set-DgVerboseLogging -Enabled $false
    $startedAt = if ($null -ne $Now) { [DateTimeOffset]$Now } else { [DateTimeOffset]::UtcNow }
    $current = { $startedAt.Add($clock.Elapsed) }
    if (-not $JobId) {
        $automationJob = Get-Variable -Name PSPrivateMetadata -Scope Global -ValueOnly -ErrorAction SilentlyContinue
        $JobId = if ($automationJob -and $automationJob.JobId) { [string]$automationJob.JobId } else { [guid]::NewGuid().ToString() }
    }
    $JobId = $JobId.ToLowerInvariant()
    if (-not $Config) { $Config = @{} }
    if (-not $AccessMode) { $AccessMode = if ([string]$Config['AccessMode'] -eq 'read-write') { 'read-write' } else { 'read-only' } }
    if (-not $TickMinutes) { $TickMinutes = if ($Config['TickMinutes']) { [int]$Config['TickMinutes'] } else { 15 } }

    $summary = {
        param([string] $Result, [string] $Message, $Definitions)
        $failedNames = [string[]]@($Definitions | Where-Object { $_.Result -in @('Blocked', 'Error') } | ForEach-Object {
                $reason = [string]$_.Error
                if ($reason.Length -gt 80) { $reason = $reason.Substring(0, 77) + '...' }
                "$($_.Name) ($($_.Result): $reason)"
            })
        [pscustomobject]@{
            PSTypeName        = 'Dg.SyncResult'
            Provider          = $Provider
            Mode              = $Mode
            JobId             = $JobId
            AccessMode        = $AccessMode
            Result            = $Result
            Message           = $Message
            Definitions       = [object[]]@($Definitions)
            FailedDefinitions = $failedNames
            DurationMs        = $clock.ElapsedMilliseconds
        }
    }

    if (-not $PSCmdlet.ShouldProcess("$Provider groups", 'Sync')) { return & $summary 'Succeeded' 'WhatIf: nothing done' @() }

    # 1. Connect
    if (-not $Store -or -not $GraphDirectory -or ($Provider -eq 'Exchange' -and -not $ExchangeDirectory)) {
        $connection = Connect-DgService -Provider $Provider -Config $Config
        if (-not $Store) { $Store = $connection.Store }
        if (-not $GraphDirectory) { $GraphDirectory = $connection.Graph }
        if (-not $ExchangeDirectory) { $ExchangeDirectory = $connection.Exchange }
    }
    $target = if ($Provider -eq 'Exchange') { $ExchangeDirectory } else { $GraphDirectory }
    $leaseMinutes = 2 * $TickMinutes

    # 2. Run lock
    $lock = Enter-DgRunLock -Store $Store -Provider $Provider -JobId $JobId -Now (& $current) -LeaseMinutes $leaseMinutes
    if (-not $lock.Acquired -and $Mode -eq 'SyncNow') {
        for ($try = 1; $try -le 8 -and -not $lock.Acquired; $try++) {
            & $Sleep 15
            $lock = Enter-DgRunLock -Store $Store -Provider $Provider -JobId $JobId -Now (& $current) -LeaseMinutes $leaseMinutes
        }
    }
    if (-not $lock.Acquired) {
        $deferred = $Mode -eq 'SyncNow'
        $reason = if ($deferred) {
            "deferred: job $($lock.HeldBy) still holds the run lock; the next scheduled run handles the request"
        } else {
            "job $($lock.HeldBy) still holds the run lock"
        }
        $record = New-DgSystemRunDocument -JobId $JobId -Provider $Provider -Mode $Mode -StartedAt $startedAt -DurationMs $clock.ElapsedMilliseconds -Result SkippedTick -Reason $reason
        [void](Set-DgStoreItem -Store $Store -Container runs -Document $record)
        return & $summary $(if ($deferred) { 'Deferred' } else { 'SkippedTick' }) $reason @()
    }

    $userCount = $null
    $paused = $false
    try {
        # 3. Settings
        $settingsDocument = Get-DgStoreItem -Store $Store -Container config -Id 'settings' -PartitionKey 'settings'
        # A new installation has no settings document until someone opens the web app (the API
        # creates it; the engine can only read config). Until then the defaults apply.
        if (-not $settingsDocument) { $settingsDocument = New-DgDefaultSettingDocument }
        $settings = ConvertTo-DgSetting -Document $settingsDocument
        Set-DgVerboseLogging -Enabled ([bool]$settingsDocument['verboseLogging'])
        $paused = $settings.Paused
        $previousHeartbeat = Get-DgStoreItem -Store $Store -Container state -Id "heartbeat-$Provider" -PartitionKey 'system'
        if ($previousHeartbeat -and $null -ne $previousHeartbeat['userCount']) { $userCount = [int]$previousHeartbeat['userCount'] }
        if ($paused) {
            $by = [string]$settingsDocument['pausedBy']
            $reason = if ($by) { "paused by $by" } else { 'paused' }
            $record = New-DgSystemRunDocument -JobId $JobId -Provider $Provider -Mode $Mode -StartedAt $startedAt -DurationMs $clock.ElapsedMilliseconds -Result Paused -Reason $reason
            [void](Set-DgStoreItem -Store $Store -Container runs -Document $record)
            return & $summary 'Paused' $reason @()
        }
        if ($Provider -eq 'Exchange' -and $settings.MarkerEnabled) { $ExchangeDirectory.MarkerAttribute = $settings.ExchangeCustomAttribute }
        if ($Provider -eq 'Entra' -and -not $settings.MarkerEnabled) { $GraphDirectory.MarkerExtension = $null }

        # 4. Definitions and what is due
        $statusById = @{}
        foreach ($status in (Find-DgStoreItem -Store $Store -Container state -Type status)) { $statusById[[string]$status['pk']] = $status }
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($definition in (Find-DgStoreItem -Store $Store -Container config -Type definition)) {
            $items.Add((ConvertTo-DgWorkItem -Definition $definition -Status $statusById[[string]$definition['id']]))
        }
        $due = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $items) {
            if ($item.Provider -ne $Provider) { continue }
            if (Test-DgDefinitionDue -Item $item -Now $startedAt -TickMinutes $TickMinutes -Mode $Mode -DefinitionId $DefinitionId) { $due.Add($item) }
        }
        Write-DgVerbose -Message "$($due.Count) of $($items.Count) definitions due"
        if ($due.Count -eq 0) {
            return & $summary 'Succeeded' 'nothing due' @()
        }

        # 5. Users, once
        $snapshotError = $null
        $users = [object[]]@()
        try {
            $fields = Get-DgSnapshotField -Rules ([string[]]@($items | ForEach-Object { $_.Rule }))
            $users = Get-DgDirectoryUser -Directory $GraphDirectory -Select $fields.Select -ExpandManager:$fields.ExpandManager
            $snapshotError = Test-DgSnapshotHealth -UserCount $users.Count -PreviousUserCount $userCount
        } catch {
            $snapshotError = "reading the users failed: $($_.Exception.Message)"
        }
        if ($snapshotError) {
            # Nothing is written: the definitions keep their state and run again next tick.
            return & $summary 'Failed' $snapshotError @()
        }
        $userCount = $users.Count
        Write-DgVerbose -Message "$userCount users read with fields $($fields.Select -join ', ')"
        $usersById = @{}
        foreach ($user in $users) { $usersById[[string](Get-DgFieldValue -Object $user -Name 'id')] = $user }

        # 6. Evaluate
        $evaluations = @{}
        $syncGraphDirectory = $GraphDirectory
        $memberProvider = {
            param([string] $GroupId, [bool] $Transitive)
            Get-DgDirectoryUserMemberId -Directory $syncGraphDirectory -GroupId $GroupId -Transitive $Transitive
        }
        $results = Invoke-DgDefinitionEvaluation -Definitions $items.ToArray() -TargetIds ([string[]]@($due | ForEach-Object { $_.Id })) `
            -Users $users -Now $startedAt -NestedMembers $settings.NestedMembers -GroupMemberProvider $memberProvider
        foreach ($result in $results) { $evaluations[$result.DefinitionId] = $result }

        # 7. Sync each due definition
        $recipients = $null
        if ($Provider -eq 'Exchange') {
            try {
                $recipients = Get-DgRecipientMap -Directory $ExchangeDirectory
            } catch {
                $message = "reading the Exchange recipients failed: $($_.Exception.Message)"
                foreach ($item in $due) { $evaluations[$item.Id] = [pscustomobject]@{ DefinitionId = $item.Id; Status = 'Error'; Error = $message; Desired = $null } }
            }
        }
        $context = @{
            Store = $Store; Provider = $Provider; Mode = $Mode; JobId = $JobId; Now = $startedAt; AccessMode = $AccessMode
            Settings = $settings; Graph = $GraphDirectory; Target = $target; Users = $users; UsersById = $usersById; Recipients = $recipients
        }
        $outcomes = [System.Collections.Generic.List[object]]::new()
        $stoppedEarly = 0
        foreach ($item in $due) {
            if ($clock.Elapsed -ge $MaxRunTime) { $stoppedEarly++; continue }
            $lock = Update-DgRunLock -Store $Store -Lock $lock -Now (& $current) -LeaseMinutes $leaseMinutes -Confirm:$false
            $evaluation = $evaluations[$item.Id]
            if (-not $evaluation) { $evaluation = [pscustomobject]@{ DefinitionId = $item.Id; Status = 'Error'; Error = 'the definition was not evaluated'; Desired = $null } }
            try {
                $outcome = Invoke-DgDefinitionSync -Item $item -Evaluation $evaluation -Context $context -Confirm:$false
                $outcomes.Add($outcome)
                Write-DgVerbose -Message (Format-DgOutcomeLine -Outcome $outcome)
            } catch {
                $outcomes.Add([pscustomobject]@{
                        DefinitionId = $item.Id; Name = $item.Name; Result = 'Error'; Error = "storing the result failed: $($_.Exception.Message)"
                        Added = 0; Removed = 0; Written = $false; RunId = $null; Warnings = [string[]]@(); DurationMs = 0
                    })
            }
        }

        $failed = @($outcomes | Where-Object { $_.Result -in @('Blocked', 'Error') })
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add("$($outcomes.Count) definitions synced")
        if ($failed.Count) { $parts.Add("$($failed.Count) blocked or failed") }
        if ($stoppedEarly) { $parts.Add("stopped after $([int]$MaxRunTime.TotalMinutes) minutes, $stoppedEarly left for the next tick") }
        $jobResult = if ($failed.Count -or $stoppedEarly) { 'Failed' } else { 'Succeeded' }
        return & $summary $jobResult ($parts -join '; ') $outcomes
    } finally {
        try {
            [void](Write-DgHeartbeat -Store $Store -Provider $Provider -JobId $JobId -Now (& $current) -Paused $paused -AccessMode $AccessMode -UserCount $userCount -Confirm:$false)
        } catch {
            Write-Warning -Message "The heartbeat could not be written: $($_.Exception.Message)"
        }
        try {
            [void](Exit-DgRunLock -Store $Store -Lock $lock.Lock)
        } catch {
            Write-Warning -Message "The run lock could not be released (it expires by itself): $($_.Exception.Message)"
        }
    }
}
