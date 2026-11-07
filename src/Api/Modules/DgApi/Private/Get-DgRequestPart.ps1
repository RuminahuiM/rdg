function Get-DgRequestPart {
    <#
    .SYNOPSIS
        Reads Headers, Query, Params, Body or RawBody from the host's request object (a hashtable
        in tests and the local host, an HttpRequestContext in Azure Functions).
    .EXAMPLE
        Get-DgRequestPart -Request $Request -Name Query
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [Parameter(Mandatory)]
        [ValidateSet('Method', 'Headers', 'Query', 'Params', 'Body', 'RawBody')]
        [string] $Name
    )

    if ($Request -is [System.Collections.IDictionary]) {
        if ($Request.Contains($Name)) { return , $Request[$Name] }
        return $null
    }
    $property = $Request.PSObject.Properties[$Name]
    if ($property) { return , $property.Value }
    $null
}
