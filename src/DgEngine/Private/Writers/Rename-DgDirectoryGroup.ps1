function Rename-DgDirectoryGroup {
    <#
    .SYNOPSIS
        Renames a group in place: same object ID, mail address and references.
    .EXAMPLE
        Rename-DgDirectoryGroup -Directory $graph -Group $group -DisplayName 'DG-Board'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [pscustomobject] $Group,

        [Parameter(Mandatory)]
        [string] $DisplayName
    )

    if (-not $PSCmdlet.ShouldProcess($Group.DisplayName, "Rename to $DisplayName")) { return }
    switch ($Directory.Kind) {
        'Custom' { & $Directory.RenameGroup -Group $Group -DisplayName $DisplayName }
        'Graph' { [void](Invoke-DgGraphRequest -Directory $Directory -Method PATCH -Uri "/groups/$($Group.Id)" -Body @{ displayName = $DisplayName }) }
        'Exchange' {
            [void](Invoke-DgExchangeCommand -Directory $Directory -Command 'Set-DistributionGroup' -Parameters @{
                    Identity = $Group.Identity; DisplayName = $DisplayName; BypassSecurityGroupManagerCheck = $true
                })
        }
    }
}
