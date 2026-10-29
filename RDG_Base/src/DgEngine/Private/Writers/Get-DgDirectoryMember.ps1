function Get-DgDirectoryMember {
    <#
    .SYNOPSIS
        Reads a group's direct members as objects with Id (Entra object ID) and IsUser.
    .DESCRIPTION
        For the diff: non-user members (groups, contacts, devices) are returned with
        IsUser = false so the engine can leave them alone. Group is the object from
        Get-DgDirectoryGroup.
    .EXAMPLE
        Get-DgDirectoryMember -Directory $graph -Group $group
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [pscustomobject] $Group
    )

    switch ($Directory.Kind) {
        'Custom' { return , [object[]]@(& $Directory.GetMembers -Group $Group) }
        'Graph' {
            $items = Get-DgGraphCollection -Directory $Directory -Uri "/groups/$($Group.Id)/members?`$select=id&`$top=999"
            return , [object[]]@($items | ForEach-Object {
                    [pscustomobject]@{
                        Id     = [string](Get-DgFieldValue -Object $_ -Name 'id')
                        IsUser = [string](Get-DgFieldValue -Object $_ -Name '@odata.type') -eq '#microsoft.graph.user'
                    }
                })
        }
        'Exchange' {
            $items = @(Invoke-DgExchangeCommand -Directory $Directory -Command 'Get-DistributionGroupMember' -Parameters @{
                    Identity = $Group.Identity; ResultSize = 'Unlimited'
                })
            return , [object[]]@($items | Where-Object { $null -ne $_ } | ForEach-Object {
                    [pscustomobject]@{
                        Id     = [string](Get-DgFieldValue -Object $_ -Name 'ExternalDirectoryObjectId')
                        IsUser = [string](Get-DgFieldValue -Object $_ -Name 'RecipientType') -in @('UserMailbox', 'MailUser')
                    }
                })
        }
    }
}
