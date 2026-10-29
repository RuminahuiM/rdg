function Get-DgOpenApi {
    <#
    .SYNOPSIS
        The API contract (openapi.json next to the module), loaded once per worker.
    .EXAMPLE
        (Get-DgOpenApi).info.version
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not $script:DgApiOpenApi) {
        $path = Join-Path -Path $PSScriptRoot -ChildPath '../openapi.json'
        $script:DgApiOpenApi = Get-Content -Raw -Path $path | ConvertFrom-Json -AsHashtable
    }
    $script:DgApiOpenApi
}
