function Get-DgChangeList {
    <#
    .SYNOPSIS
        Lists the fields that differ between two versions of a document, as audit changes
        { field, old, new }. Values are compared by their JSON form.
    .EXAMPLE
        Get-DgChangeList -Old $current -New $updated -Fields @('name', 'rule')
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowNull()]
        [System.Collections.IDictionary] $Old,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $New,

        [Parameter(Mandatory)]
        [string[]] $Fields
    )

    foreach ($field in $Fields) {
        # Plain assignment: an if-expression would turn an empty list into $null.
        $before = $null
        if ($Old) { $before = $Old[$field] }
        $after = $New[$field]
        $beforeJson = ConvertTo-Json -InputObject $before -Depth 20 -Compress
        $afterJson = ConvertTo-Json -InputObject $after -Depth 20 -Compress
        if ($beforeJson -ceq $afterJson) { continue }
        [ordered]@{ field = $field; old = $before; new = $after }
    }
}
