function ConvertTo-DgAssignedGroup {
    <#
    .SYNOPSIS
        Turns a Microsoft dynamic group into an assigned (static) group, keeping its members.
    .DESCRIPTION
        Removes DynamicMembership from groupTypes and pauses rule processing, the way Microsoft's
        own sample does. Members are kept (to be confirmed in the test tenant, step 8.5). Only
        for Entra groups; Exchange dynamic distribution groups are separate objects RDG doesn't adopt.
    .EXAMPLE
        ConvertTo-DgAssignedGroup -Directory $graph -Group $group
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [pscustomobject] $Group
    )

    if (-not $Group.IsDynamic) { return }
    if (-not $PSCmdlet.ShouldProcess($Group.DisplayName, 'Switch from dynamic to assigned membership')) { return }
    switch ($Directory.Kind) {
        'Custom' { & $Directory.ConvertToAssigned -Group $Group }
        'Graph' {
            $types = [string[]]@($Group.GroupTypes | Where-Object { $_ -ne 'DynamicMembership' })
            [void](Invoke-DgGraphRequest -Directory $Directory -Method PATCH -Uri "/groups/$($Group.Id)" -Body @{
                    groupTypes = $types; membershipRuleProcessingState = 'Paused'
                })
        }
        default { throw "only Entra dynamic groups can be converted, not $($Directory.Kind) groups" }
    }
}
