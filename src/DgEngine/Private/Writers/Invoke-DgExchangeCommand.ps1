function Invoke-DgExchangeCommand {
    <#
    .SYNOPSIS
        Runs one Exchange Online cmdlet through the directory's Invoke, with retries on throttling.
    .EXAMPLE
        Invoke-DgExchangeCommand -Directory $exchange -Command 'Get-DistributionGroup' -Parameters @{ Filter = "..." }
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [string] $Command,

        [Parameter(Mandatory)]
        [hashtable] $Parameters
    )

    # Copied into locals so the closure captures them.
    $invoke = $Directory.Invoke
    $name = $Command
    $arguments = $Parameters
    Invoke-DgWithRetry -Sleep $Directory.Sleep -ScriptBlock {
        & $invoke -Command $name -Parameters $arguments
    }.GetNewClosure()
}
