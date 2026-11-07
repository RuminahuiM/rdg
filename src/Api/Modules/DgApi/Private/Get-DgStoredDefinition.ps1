function Get-DgStoredDefinition {
    <#
    .SYNOPSIS
        Reads one definition and its status; 404 when the definition doesn't exist.
    .EXAMPLE
        $stored = Get-DgStoredDefinition -Context $Context -Id $id
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context,

        [AllowNull()]
        [string] $Id
    )

    if ($Id -notmatch '^def-[0-9A-HJKMNP-TV-Z]{26}$') { Stop-DgApi -Status 404 -Title 'Definition not found' }
    $definition = Invoke-DgEngine -Name Get-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'config'; Id = $Id; PartitionKey = $Id }
    if (-not $definition -or $definition['type'] -ne 'definition') { Stop-DgApi -Status 404 -Title 'Definition not found' -Detail "no definition $Id" }
    $status = Invoke-DgEngine -Name Get-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'state'; Id = "status-$Id"; PartitionKey = $Id }
    [pscustomobject]@{ Definition = $definition; Status = $status }
}
