function Invoke-DgApiFunction {
    <#
    .SYNOPSIS
        Entry point for every HTTP function: finds the operation for the function's route and the
        request's method in openapi.yaml and handles it with Invoke-DgApiRequest.
    .DESCRIPTION
        Routes in function.json are the OpenAPI paths without the leading slash, so the contract
        alone decides which operation runs (and which roles it needs). A method the contract
        doesn't define for the route answers 405.
    .EXAMPLE
        Invoke-DgApiFunction -Route 'definitions/{id}' -Request $Request
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Route,

        [Parameter(Mandatory)]
        [object] $Request
    )

    $path = '/' + $Route.Trim('/')
    $method = ([string](Get-DgRequestPart -Request $Request -Name 'Method')).ToLowerInvariant()
    $api = Get-DgOpenApi
    $operation = if ($api.paths.ContainsKey($path) -and $api.paths[$path] -is [System.Collections.IDictionary]) { $api.paths[$path][$method] } else { $null }
    if (-not $operation -or $operation -isnot [System.Collections.IDictionary]) {
        $response = New-DgApiResponse -Status 405 -ContentType 'application/problem+json' -Body ([ordered]@{
                type = 'https://rdg.invalid/problems/method-not-allowed'; title = 'Method not allowed'; status = 405
                correlationId = [guid]::NewGuid().ToString()
            })
        return $response
    }
    Invoke-DgApiRequest -OperationId ([string]$operation['operationId']) -Request $Request
}
