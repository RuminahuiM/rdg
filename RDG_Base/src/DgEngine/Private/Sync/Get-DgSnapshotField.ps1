function Get-DgSnapshotField {
    <#
    .SYNOPSIS
        Works out which Graph user fields a set of rules needs, and whether any rule uses
        Direct Reports (then the manager is expanded).
    .DESCRIPTION
        Invalid rules are skipped here; their definitions fail with the parse error later.
    .EXAMPLE
        Get-DgSnapshotField -Rules @('user.department -eq "Sales"')   # Select: department
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Rules
    )

    $fields = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $expandManager = $false
    foreach ($rule in $Rules) {
        try {
            $ast = ConvertTo-DgRuleAst -Rule $rule
        } catch {
            continue
        }
        $reference = Get-DgRuleReference -Ast $ast
        if ($reference.UsesManager) { $expandManager = $true }
        foreach ($name in $reference.Properties) {
            $entry = Resolve-DgRuleProperty -Name $name
            if ($entry -and $entry.Select) { [void]$fields.Add($entry.Select) }
        }
    }
    [pscustomobject]@{
        Select        = [string[]]@($fields)
        ExpandManager = $expandManager
    }
}
