function Invoke-DgEngine {
    <#
    .SYNOPSIS
        Calls a DgEngine function, including the engine's internal ones (store, directory adapters),
        so the API reuses exactly the code the runbooks use.
    .EXAMPLE
        Invoke-DgEngine -Name Get-DgStoreItem -Parameters @{ Store = $store; Container = 'config'; Id = 'settings'; PartitionKey = 'settings' }
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]+-Dg[A-Za-z]+$')]
        [string] $Name,

        [hashtable] $Parameters = @{}
    )

    $engine = Get-Module -Name DgEngine
    & $engine { param($command, $arguments) & $command @arguments } $Name $Parameters
}
