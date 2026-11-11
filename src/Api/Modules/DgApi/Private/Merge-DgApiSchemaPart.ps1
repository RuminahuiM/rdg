function Merge-DgApiSchemaPart {
    <#
    .SYNOPSIS
        Merges two schema objects that must both hold into one; $null when they constrain the same
        keyword in a way a plain merge would change.
    .EXAMPLE
        Merge-DgApiSchemaPart -Outer $node -Inner $resolvedReference
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Outer,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Inner
    )

    $annotations = @('description', 'title', '$comment', 'examples', 'example', 'deprecated', 'readOnly', 'writeOnly')
    # additionalProperties and patternProperties only see the properties of their own part, and
    # unevaluatedProperties in the inner part doesn't see the outer one; merging would change that.
    # unevaluatedProperties in the outer part already sees both, so it may stay.
    foreach ($key in 'additionalProperties', 'patternProperties') {
        if ($Outer.Contains($key) -and $Inner.Contains('properties')) { return $null }
        if ($Inner.Contains($key) -and $Outer.Contains('properties')) { return $null }
    }
    if ($Inner.Contains('unevaluatedProperties') -and $Outer.Contains('properties')) { return $null }
    foreach ($key in $Inner.Keys) {
        if (-not $Outer.Contains($key) -or $key -in $annotations -or $key -eq 'required') { continue }
        if ($key -eq 'properties') {
            foreach ($name in $Inner[$key].Keys) { if ($Outer[$key].Contains($name)) { return $null } }
            continue
        }
        return $null
    }

    $merged = [ordered]@{}
    foreach ($key in $Inner.Keys) { $merged[$key] = $Inner[$key] }
    foreach ($key in $Outer.Keys) {
        if ($key -eq 'required' -and $merged.Contains('required')) {
            $merged[$key] = @(@($merged[$key]) + @($Outer[$key]) | Select-Object -Unique)
        } elseif ($key -eq 'properties' -and $merged.Contains('properties')) {
            $properties = [ordered]@{}
            foreach ($name in $merged[$key].Keys) { $properties[$name] = $merged[$key][$name] }
            foreach ($name in $Outer[$key].Keys) { $properties[$name] = $Outer[$key][$name] }
            $merged[$key] = $properties
        } else {
            $merged[$key] = $Outer[$key]
        }
    }
    $merged
}
