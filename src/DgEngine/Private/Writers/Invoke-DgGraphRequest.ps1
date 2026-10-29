function Invoke-DgGraphRequest {
    <#
    .SYNOPSIS
        One Graph call with retries. Uri may be relative to the v1.0 base or absolute (next links).
    .EXAMPLE
        Invoke-DgGraphRequest -Directory $graph -Method GET -Uri '/groups/<id>'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [object] $Body
    )

    $absolute = if ($Uri.StartsWith('https://')) { $Uri } else { $Directory.BaseUri + $Uri }
    # Copied into locals so the closure captures them (the closure cannot see this function's scope later).
    $request = $Directory.Request
    $verb = $Method
    $payload = $Body
    # The API sets MaxAttempts low, so a throttled preview answers 429 instead of waiting.
    $attempts = if ($Directory['MaxAttempts']) { [int]$Directory['MaxAttempts'] } else { 5 }
    Invoke-DgWithRetry -Sleep $Directory.Sleep -MaxAttempts $attempts -ScriptBlock {
        & $request -Method $verb -Uri $absolute -Body $payload
    }.GetNewClosure()
}
