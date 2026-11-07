function Get-DgApiGraph {
    <#
    .SYNOPSIS
        The Graph directory for the API, connected as the "api" identity on first use. Throttling
        is retried only briefly, so a throttled call answers 429 instead of hanging.
    .EXAMPLE
        $graph = Get-DgApiGraph -Context $Context
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    if (-not $Context.Graph) {
        & $Context.ConnectGraph $Context.ClientId
        $graph = Invoke-DgEngine -Name New-DgGraphDirectory -Parameters @{
            Sleep = { param([double] $Seconds) Start-Sleep -Milliseconds ([int]([Math]::Min($Seconds, 2) * 1000)) }
        }
        $graph.MaxAttempts = 2
        $Context.Graph = $graph
    }
    $Context.Graph
}
