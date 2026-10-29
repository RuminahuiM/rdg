# Generic HTTP entry point; the same file in every function folder.
# The route in function.json is the OpenAPI path, so DgApi finds the operation (and its roles) there.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TriggerMetadata', Justification = 'Fixed signature of Azure Functions.')]
param($Request, $TriggerMetadata)

if (-not $script:DgRoute) {
    $binding = (Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath 'function.json') | ConvertFrom-Json).bindings |
        Where-Object { $_.type -eq 'httpTrigger' }
    $script:DgRoute = $binding.route
}
$response = Invoke-DgApiFunction -Route $script:DgRoute -Request $Request
$context = [HttpResponseContext]::new()
$context.StatusCode = [System.Net.HttpStatusCode]$response.StatusCode
$context.Headers = $response.Headers
$context.Body = $response.Body
Push-OutputBinding -Name Response -Value $context
