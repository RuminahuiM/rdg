function New-DgMemoryStore {
    <#
    .SYNOPSIS
        An in-memory store with the same behaviour as the Cosmos store: ETags, create conflicts,
        conditional replace and delete. Used by the tests and for local experiments.
    .DESCRIPTION
        Documents go through a JSON round trip on every write and read, like with Cosmos DB, so
        a test sees exactly what a real run would read back (including dates parsed by
        ConvertFrom-Json).
    .EXAMPLE
        $store = New-DgMemoryStore
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Kind       = 'Memory'
        Containers = @{
            config = [ordered]@{}
            state  = [ordered]@{}
            runs   = [ordered]@{}
        }
        Version    = 0
    }
}
