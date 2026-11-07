function Set-DgDirectoryMarker {
    <#
    .SYNOPSIS
        Writes the definition ID into the group's marker attribute, when the marker is configured.
    .DESCRIPTION
        Exchange: CustomAttribute<N>. Entra: the directory extension property named in the Graph
        directory's MarkerExtension. Does nothing when the marker isn't configured. An empty
        DefinitionId clears the marker (when a definition releases its group).
    .EXAMPLE
        Set-DgDirectoryMarker -Directory $exchange -Group $group -DefinitionId $definition.Id
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [pscustomobject] $Group,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $DefinitionId
    )

    $value = if ($DefinitionId) { $DefinitionId } else { $null }
    switch ($Directory.Kind) {
        'Custom' { if ($Directory.ContainsKey('SetMarker')) { & $Directory.SetMarker -Group $Group -DefinitionId $DefinitionId } }
        'Graph' {
            if (-not $Directory.MarkerExtension) { return }
            if ($PSCmdlet.ShouldProcess($Group.DisplayName, "Set $($Directory.MarkerExtension)")) {
                [void](Invoke-DgGraphRequest -Directory $Directory -Method PATCH -Uri "/groups/$($Group.Id)" -Body @{ $Directory.MarkerExtension = $value })
            }
        }
        'Exchange' {
            if ($Directory.MarkerAttribute -lt 1) { return }
            if ($PSCmdlet.ShouldProcess($Group.DisplayName, "Set CustomAttribute$($Directory.MarkerAttribute)")) {
                [void](Invoke-DgExchangeCommand -Directory $Directory -Command 'Set-DistributionGroup' -Parameters @{
                        Identity = $Group.Identity; "CustomAttribute$($Directory.MarkerAttribute)" = $value; BypassSecurityGroupManagerCheck = $true
                    })
            }
        }
    }
}
