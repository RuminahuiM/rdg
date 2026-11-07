function Add-DgUnknownPropertyError {
    <#
    .SYNOPSIS
        Reports an unknown property, suggesting the closest known name (at most 2 edits away).
    .EXAMPLE
        Add-DgUnknownPropertyError -Property $node.Property -Add $add
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Property,

        [Parameter(Mandatory)]
        [scriptblock] $Add
    )

    $name = $Property.Name
    $best = $null
    $bestDistance = 3
    foreach ($entry in (Get-DgPropertyMap).Values) {
        $distance = Get-DgEditDistance -First $name.ToLowerInvariant() -Second $entry.Name.ToLowerInvariant()
        if ($distance -lt $bestDistance) {
            $best = $entry.Name
            $bestDistance = $distance
        }
    }
    $hint = if ($best) { "; did you mean ${best}?" } else { '' }
    & $Add $Property.Position $Property.Length "unknown property user.$name$hint" $(if ($best) { $best })
}
