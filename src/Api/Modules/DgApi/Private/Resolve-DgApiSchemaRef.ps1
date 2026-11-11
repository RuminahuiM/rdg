function Resolve-DgApiSchemaRef {
    <#
    .SYNOPSIS
        Returns a copy of a contract schema with local $ref replaced by their target and
        single-entry allOf merged into their parent, wherever that keeps the meaning.
    .DESCRIPTION
        Test-Json reports an error with its path only when the failing keyword is reached through
        "properties". Errors behind $ref or allOf make the document invalid but come without a
        message, so the API could not name the field. Inlining brings the fields of the request
        body back to that level. Errors inside nested objects (for example target.mode) still
        come without a message in PowerShell 7.6 and are answered as "(body)".

        Merging is the same as the original only when the two parts don't constrain the same
        keyword. So a $ref or allOf is merged only when the parts share nothing but annotations
        (description, title, ...), "required" (combined) or "properties" with different names;
        otherwise it stays as it is and still validates through $defs. Recursion stops at a
        depth of 30 for the same reason.
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

    if ($Node -is [System.Collections.IList]) {
        $items = foreach ($item in $Node) { Resolve-DgApiSchemaRef -Node $item -Definitions $Definitions -Depth ($Depth + 1) }
        return , @($items)
    }
    if ($Node -isnot [System.Collections.IDictionary]) { return , $Node }

    $result = [ordered]@{}
    foreach ($key in $Node.Keys) {
        $result[$key] = Resolve-DgApiSchemaRef -Node $Node[$key] -Definitions $Definitions -Depth ($Depth + 1)
    }

    # $ref to a component: merge the resolved target into this node.
    $reference = if ($result.Contains('$ref')) { [string]$result['$ref'] } else { '' }
    if ($reference.StartsWith('#/$defs/') -and $Definitions.Contains($reference.Substring(8))) {
        $target = Resolve-DgApiSchemaRef -Node $Definitions[$reference.Substring(8)] -Definitions $Definitions -Depth ($Depth + 1)
        $rest = [ordered]@{}
        foreach ($key in $result.Keys) { if ($key -ne '$ref') { $rest[$key] = $result[$key] } }
        $merged = Merge-DgApiSchemaPart -Outer $rest -Inner $target
        if ($null -ne $merged) { $result = $merged }
    }

    # allOf with one entry: merge the entry into this node.
    $parts = @(if ($result.Contains('allOf')) { $result['allOf'] })
    if ($parts.Count -eq 1 -and $parts[0] -is [System.Collections.IDictionary]) {
        $rest = [ordered]@{}
        foreach ($key in $result.Keys) { if ($key -ne 'allOf') { $rest[$key] = $result[$key] } }
        $merged = Merge-DgApiSchemaPart -Outer $rest -Inner $parts[0]
        if ($null -ne $merged) { $result = $merged }
    }

    , $result
}
