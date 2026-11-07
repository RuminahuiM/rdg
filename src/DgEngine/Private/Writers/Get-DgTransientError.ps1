function Get-DgTransientError {
    <#
    .SYNOPSIS
        Tells whether an error is worth retrying, and how long the service asked to wait.
    .EXAMPLE
        Get-DgTransientError -ErrorRecord $_
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $status = $null
    $retryAfter = 0
    $exception = $ErrorRecord.Exception
    while ($exception) {
        if ($exception.Data.Contains('StatusCode')) {
            $status = [int]$exception.Data['StatusCode']
            if ($exception.Data.Contains('RetryAfter')) { $retryAfter = [int]$exception.Data['RetryAfter'] }
            break
        }
        $response = if ($exception.PSObject.Properties['Response']) { $exception.Response } else { $null }
        if ($response -and $response.PSObject.Properties['StatusCode']) {
            $status = [int]$response.StatusCode
            $headers = if ($response.PSObject.Properties['Headers']) { $response.Headers } else { $null }
            if ($headers -and $headers.PSObject.Properties['RetryAfter'] -and $headers.RetryAfter -and $headers.RetryAfter.Delta) {
                $retryAfter = [int]$headers.RetryAfter.Delta.TotalSeconds
            }
            break
        }
        $exception = $exception.InnerException
    }

    $message = $ErrorRecord.Exception.Message
    $exchangeThrottled = $message -match 'throttl|Server Busy|too many concurrent|TooManyRequests'
    [pscustomobject]@{
        Transient         = ($status -in @(429, 503, 504)) -or $exchangeThrottled
        StatusCode        = $status
        RetryAfterSeconds = $retryAfter
        Reason            = if ($status) { "HTTP $status" } elseif ($exchangeThrottled) { 'Exchange throttling' } else { 'none' }
    }
}
