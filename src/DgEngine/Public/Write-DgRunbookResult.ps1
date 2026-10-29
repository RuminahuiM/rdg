function Write-DgRunbookResult {
    <#
    .SYNOPSIS
        Turns the result of Invoke-DgSync into the runbook's job output and job status.
    .DESCRIPTION
        Output stream: one compact JSON line per definition, then one summary line.
        Warning stream: one line per warning, prefixed with the definition name.
        Error: when the run failed, one summary error is thrown at the very end, so the job
        ends as Failed and the alert fires, e.g.
        "2 definitions blocked or failed: EOP Strict (Blocked: ...), Finance (Error: ...)".
    .EXAMPLE
        Invoke-DgSync -Provider Entra -Config $config | Write-DgRunbookResult
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [pscustomobject] $Result
    )

    process {
        foreach ($definition in $Result.Definitions) {
            [ordered]@{
                definition = $definition.Name
                result     = $definition.Result
                added      = [int]$definition.Added
                removed    = [int]$definition.Removed
                ms         = [long]$definition.DurationMs
            } | ConvertTo-Json -Compress
            foreach ($warning in @($definition.Warnings)) {
                if ($warning) { Write-Warning -Message "$($definition.Name): $warning" }
            }
            if ($definition.Result -in @('Blocked', 'Error') -and $definition.Error) {
                Write-Warning -Message "$($definition.Name): $($definition.Error)"
            }
        }
        [ordered]@{
            provider    = $Result.Provider
            mode        = $Result.Mode
            accessMode  = $Result.AccessMode
            jobId       = $Result.JobId
            result      = $Result.Result
            message     = $Result.Message
            definitions = @($Result.Definitions).Count
            ms          = [long]$Result.DurationMs
        } | ConvertTo-Json -Compress

        if ($Result.Result -eq 'Failed') {
            $failed = @($Result.FailedDefinitions)
            $text = if ($failed.Count) {
                "$($failed.Count) definitions blocked or failed: $($failed -join ', ')"
            } else {
                "the run failed: $($Result.Message)"
            }
            if ($failed.Count -and $Result.Message -like '*stopped after*') { $text += "; $($Result.Message)" }
            throw $text
        }
    }
}
