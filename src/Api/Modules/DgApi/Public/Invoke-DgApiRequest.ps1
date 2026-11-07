function Invoke-DgApiRequest {
    <#
    .SYNOPSIS
        Handles one API request: identifies the caller, checks the role from openapi.yaml, runs the
        operation's handler and turns every failure into an RFC 9457 problem with a correlation ID.
    .DESCRIPTION
        Each Azure Function's run.ps1 calls this with its operationId. Returns a hashtable with
        StatusCode, Headers and Body (JSON text) for the host's HTTP response.
        - Problems raised by handlers (Stop-DgApi) keep their status.
        - Graph throttling that outlasted the short retry becomes 429 with Retry-After.
        - Anything else becomes 500; the log line carries the same correlation ID.
    .EXAMPLE
        $response = Invoke-DgApiRequest -OperationId getMe -Request $Request
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-zA-Z]+$')]
        [string] $OperationId,

        [Parameter(Mandatory)]
        [object] $Request
    )

    $correlationId = [guid]::NewGuid().ToString()
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $problemResponse = {
        param([System.Collections.IDictionary] $Problem)
        $Problem['correlationId'] = $correlationId
        $response = New-DgApiResponse -Status ([int]$Problem['status']) -Body $Problem -ContentType 'application/problem+json'
        if ($Problem.Contains('retryAfterSeconds')) { $response.Headers['Retry-After'] = [string]$Problem['retryAfterSeconds'] }
        $response
    }

    $caller = $null
    try {
        $operation = Get-DgApiOperation -OperationId $OperationId
        $context = Get-DgApiContext
        if ($operation.Roles -notcontains 'anonymous' -and $operation.Roles -notcontains 'static-web-app') {
            $caller = Get-DgCaller -Request $Request
            Assert-DgRole -Caller $caller -Allowed $operation.Roles
        }
        $handler = 'Invoke-DgApi' + $OperationId.Substring(0, 1).ToUpperInvariant() + $OperationId.Substring(1)
        $response = & $handler -Request $Request -Caller $caller -Context $context
    } catch {
        $exception = $_.Exception
        $problem = $exception.Data['DgProblem']
        if (-not $problem) {
            $transient = Invoke-DgEngine -Name Get-DgTransientError -Parameters @{ ErrorRecord = $_ }
            if ($transient.StatusCode -in @(429, 503, 504)) {
                $wait = if ($transient.RetryAfterSeconds -gt 0) { $transient.RetryAfterSeconds } else { 10 }
                $problem = [ordered]@{
                    type = 'https://rdg.invalid/problems/too-many-requests'; title = 'Microsoft Graph is busy'; status = 429
                    detail = "try again in $wait seconds"; retryAfterSeconds = [int]$wait
                }
            } else {
                Write-Error -Message "[$correlationId] $OperationId failed: $($exception.Message)`n$($_.ScriptStackTrace)" -ErrorAction Continue
                $problem = [ordered]@{
                    type = 'https://rdg.invalid/problems/server-error'; title = 'Unexpected error'; status = 500
                    detail = 'the error was logged with this correlation ID'
                }
            }
        }
        $response = & $problemResponse $problem
    }
    $response.Headers['x-correlation-id'] = $correlationId
    $who = if ($caller) { $caller.Upn } else { '-' }
    Write-Information -MessageData "[$correlationId] $OperationId $($response.StatusCode) $who $($clock.ElapsedMilliseconds)ms"
    $response
}
