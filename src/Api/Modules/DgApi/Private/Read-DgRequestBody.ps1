function Read-DgRequestBody {
    <#
    .SYNOPSIS
        Reads the JSON request body, validates it against an OpenAPI schema and returns it as a
        hashtable. Invalid JSON or a body that breaks the contract ends with 400.
    .EXAMPLE
        $input = Read-DgRequestBody -Request $Request -Schema DefinitionInput
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [Parameter(Mandatory)]
        [string] $Schema
    )

    $raw = Get-DgRequestPart -Request $Request -Name 'RawBody'
    if (-not $raw) {
        $body = Get-DgRequestPart -Request $Request -Name 'Body'
        if ($body -is [string]) { $raw = $body }
        elseif ($null -ne $body) { $raw = ConvertTo-Json -InputObject $body -Depth 30 -Compress }
    }
    if (-not $raw) { Stop-DgApi -Status 400 -Title 'Request body missing' -Type 'validation' }
    if ($raw.Length -gt 200000) { Stop-DgApi -Status 400 -Title 'Request body too large' -Type 'validation' }
    try {
        $parsed = ConvertFrom-Json -InputObject $raw -AsHashtable -ErrorAction Stop
    } catch {
        Stop-DgApi -Status 400 -Title 'Request body is not valid JSON' -Type 'validation'
    }
    if ($parsed -isnot [hashtable]) { Stop-DgApi -Status 400 -Title 'Request body must be a JSON object' -Type 'validation' }
    $errors = @(Test-DgApiSchema -Json $raw -Schema $Schema)
    if ($errors.Count) {
        Stop-DgApi -Status 400 -Title 'Request body is not valid' -Type 'validation' -Extra @{ errors = $errors }
    }
    $parsed
}
