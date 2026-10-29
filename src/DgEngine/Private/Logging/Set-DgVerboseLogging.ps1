function Set-DgVerboseLogging {
    <#
    .SYNOPSIS
        Turns the engine's own verbose log (Write-DgVerbose) on or off for this run.
    .EXAMPLE
        Set-DgVerboseLogging -Enabled $true
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Sets an in-memory flag only; changes no system state.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool] $Enabled
    )

    $script:DgVerboseLogging = $Enabled
}
