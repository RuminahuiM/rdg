function Test-DgApiSchema {
    <#
    .SYNOPSIS
        Validates JSON text against a component schema of the OpenAPI contract and returns the
        errors as { field, message } (none when valid).
    .DESCRIPTION
        The contract comes from openapi.json next to the module (generated from openapi.yaml).
        Pass or fail comes from Test-Json (JSON Schema 2020-12). The validator also reports
        follow-up noise for unknown fields and if/then branches; those messages are dropped when
        a more specific one exists.
    .EXAMPLE
        Test-DgApiSchema -Json $raw -Schema DefinitionInput
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $Json,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]+$')]
        [string] $Schema
    )

    if (-not $script:DgApiSchemas.ContainsKey($Schema)) {
        $definitions = (ConvertTo-Json -InputObject (Get-DgOpenApi).components.schemas -Depth 60 -Compress) -replace '#/components/schemas/', '#/$defs/'
        $script:DgApiSchemas[$Schema] = '{"$schema":"https://json-schema.org/draft/2020-12/schema","$ref":"#/$defs/' + $Schema + '","$defs":' + $definitions + '}'
    }
    $failures = $null
    $valid = Test-Json -Json $Json -Schema $script:DgApiSchemas[$Schema] -ErrorVariable failures -ErrorAction SilentlyContinue
    if ($valid) { return }

    $entries = foreach ($failure in @($failures)) {
        $text = [string]$failure.Exception.Message -replace '^The JSON is not valid with the schema: ', ''
        $path = if ($text -match " at '([^']*)'$") { $Matches[1] } else { '' }
        $message = $text -replace " at '[^']*'$", ''
        $falseSchema = $message -like '*false schema*'
        $segments = @($path.Trim('/') -split '/' | Where-Object { $_ })
        if ($falseSchema -and $segments.Count -ge 2 -and $segments[-1] -eq $segments[-2]) { $segments = $segments[0..($segments.Count - 2)] }
        [pscustomobject]@{
            Field   = if ($segments.Count) { $segments -join '.' } else { '(body)' }
            Message = if ($falseSchema) { 'unknown field' } else { $message -replace '\\u0022', '"' }
            Noise   = $falseSchema -or $message -like 'Expected "*'
        }
    }
    $specific = @($entries | Where-Object { -not $_.Noise })
    $unknown = @($entries | Where-Object { $_.Message -eq 'unknown field' })
    $chosen = @(if ($specific.Count) { $specific } elseif ($unknown.Count) { $unknown } else { $entries })
    if (-not $chosen.Count) { $chosen = @([pscustomobject]@{ Field = '(body)'; Message = 'does not match the contract' }) }
    $seen = @{}
    foreach ($entry in $chosen) {
        $key = "$($entry.Field)|$($entry.Message)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [ordered]@{ field = $entry.Field; message = $entry.Message }
    }
}
