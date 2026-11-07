function Invoke-DgWithRetry {
    <#
    .SYNOPSIS
        Runs a call and retries it when the service throttles or is briefly unavailable.
    .DESCRIPTION
        Retries on HTTP 429, 503 and 504 (Graph, Cosmos DB) and on Exchange throttling errors,
        up to MaxAttempts. Waits as long as the service asks (Retry-After), otherwise
        exponentially: 2, 4, 8, 16 s. Any other error is thrown at once.
        The status code is read from the exception's response (Invoke-MgGraphRequest,
        Invoke-WebRequest) or from Exception.Data['StatusCode'] (tests, own adapters).
    .EXAMPLE
        Invoke-DgWithRetry -ScriptBlock { Invoke-MgGraphRequest -Uri $uri } -Sleep { param($s) Start-Sleep -Seconds $s }
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory)]
        [scriptblock] $Sleep,

        [ValidateRange(1, 10)]
        [int] $MaxAttempts = 5
    )

    for ($attempt = 1; ; $attempt++) {
        try {
            return & $ScriptBlock
        } catch {
            $info = Get-DgTransientError -ErrorRecord $_
            if (-not $info.Transient -or $attempt -ge $MaxAttempts) {
                throw
            }
            $wait = if ($info.RetryAfterSeconds -gt 0) { [Math]::Min($info.RetryAfterSeconds, 120) } else { [Math]::Pow(2, $attempt) }
            Write-DgVerbose -Message "Transient error ($($info.Reason)); retry $attempt of $($MaxAttempts - 1) in $wait s"
            & $Sleep $wait
        }
    }
}
