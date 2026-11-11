function Resolve-DgApiSchemaRef {
    <#
    .SYNOPSIS
        Returns a copy of a contract schema with every local $ref replaced by its target and
        every single-entry allOf merged into its parent.
    .DESCRIPTION
        Test-Json reports an error with its path only when the failing keyword is reached through
        "properties". Errors behind $ref or allOf make the document invalid but come without a
        message, so the API could not name the field. The inlined schema validates the same
        documents and keeps the messages. Recursion stops at a depth of 30; deeper $ref stay as
        they are and still resolve through $defs.
    .EXAMPLE
        Resolve-DgApiSchemaRef -Node $schemas['DefinitionInput'] -Definitions $schemas
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [AllowNull()]
        [object] $Node,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Definitions,

        [int] $Depth = 0
    )

    if ($Depth -gt 30) { return , $Node }

    if ($Node -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        $reference = if ($Node.Contains('$ref')) { [string]$Node['$ref'] } else { '' }
        $resolved = $reference.StartsWith('#/$defs/') -and $Definitions.Contains($reference.Substring(8))
        if ($resolved) {
            $target = Resolve-DgApiSchemaRef -Node $Definitions[$reference.Substring(8)] -Definitions $Definitions -Depth ($Depth + 1)
            foreach ($key in $target.Keys) { $result[$key] = $target[$key] }
        }
        foreach ($key in $Node.Keys) {
            if ($resolved -and $key -eq '$ref') { continue }
            $result[$key] = Resolve-DgApiSchemaRef -Node $Node[$key] -Definitions $Definitions -Depth ($Depth + 1)
        }

        $parts = @(if ($result.Contains('allOf')) { $result['allOf'] })
        if ($parts.Count -eq 1 -and $parts[0] -is [System.Collections.IDictionary]) {
            $part = $parts[0]
            $result.Remove('allOf')
            foreach ($key in $part.Keys) {
                if (-not $result.Contains($key)) {
                    $result[$key] = $part[$key]
                } elseif ($key -eq 'required') {
                    $result[$key] = @(@($result[$key]) + @($part[$key]) | Select-Object -Unique)
                } elseif ($key -eq 'properties') {
                    $properties = [ordered]@{}
                    foreach ($name in $part[$key].Keys) { $properties[$name] = $part[$key][$name] }
                    foreach ($name in $result[$key].Keys) { $properties[$name] = $result[$key][$name] }
                    $result[$key] = $properties
                }
            }
        }
        return , $result
    }

    if ($Node -is [System.Collections.IList]) {
        $items = foreach ($item in $Node) { Resolve-DgApiSchemaRef -Node $item -Definitions $Definitions -Depth ($Depth + 1) }
        return , @($items)
    }

    , $Node
}
