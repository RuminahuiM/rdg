function New-DgExchangeDirectory {
    <#
    .SYNOPSIS
        Creates the Exchange Online directory used for mail-enabled security groups and distribution lists.
    .DESCRIPTION
        Invoke is called as & $Invoke -Command <cmdlet name> -Parameters <hashtable> and returns the
        cmdlet output. The default runs the ExchangeOnlineManagement cmdlets of the current
        session (Connect-ExchangeOnline -ManagedIdentity). Tests pass a fake.
        Groups are identified by their Entra object ID (ExternalDirectoryObjectId), like everywhere
        in RDG. MarkerAttribute is the CustomAttribute number (1-15) for the marker, or 0 when off.
    .EXAMPLE
        $exchange = New-DgExchangeDirectory -MarkerAttribute 15
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [scriptblock] $Invoke = {
            param([string] $Command, [hashtable] $Parameters)
            & $Command @Parameters -ErrorAction Stop
        },

        [scriptblock] $Sleep = { param([double] $Seconds) Start-Sleep -Milliseconds ([int]($Seconds * 1000)) },

        [ValidateRange(0, 15)]
        [int] $MarkerAttribute = 0,

        # Seconds to wait for a new group's Entra object ID to appear, in attempts of 5 s.
        [int] $CreateWaitAttempts = 12
    )

    @{
        Kind               = 'Exchange'
        Invoke             = $Invoke
        Sleep              = $Sleep
        MarkerAttribute    = $MarkerAttribute
        CreateWaitAttempts = $CreateWaitAttempts
        Recipients         = $null
    }
}
