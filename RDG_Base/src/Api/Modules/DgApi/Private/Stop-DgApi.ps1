function Stop-DgApi {
    <#
    .SYNOPSIS
        Ends the request with an RFC 9457 problem: throws an exception the dispatcher turns into
        the response.
    .EXAMPLE
        Stop-DgApi -Status 404 -Title 'Definition not found'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only throws; changes no state.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(400, 599)]
        [int] $Status,

        [Parameter(Mandatory)]
        [string] $Title,

        [string] $Detail,

        # Last part of the problem type URI, e.g. 'validation'.
        [string] $Type,

        # Extra problem fields (errors, current, referencedBy, retryAfterSeconds).
        [hashtable] $Extra = @{}
    )

    $kind = if ($Type) { $Type } else {
        switch ($Status) {
            400 { 'bad-request' } 401 { 'unauthorized' } 403 { 'forbidden' } 404 { 'not-found' } 409 { 'conflict' }
            412 { 'precondition-failed' } 428 { 'precondition-required' } 429 { 'too-many-requests' } default { 'server-error' }
        }
    }
    $problem = [ordered]@{ type = "https://rdg.invalid/problems/$kind"; title = $Title; status = $Status }
    if ($Detail) { $problem.detail = $Detail }
    foreach ($key in $Extra.Keys) { $problem[$key] = $Extra[$key] }
    $exception = [System.InvalidOperationException]::new("$Status $Title")
    $exception.Data['DgProblem'] = $problem
    throw $exception
}
