function Invoke-DgApiSearchGroups {
    <#
    .SYNOPSIS
        GET /api/directory/groups?search=: group picker, up to 25 groups by prefix, with the flags
        the pickers need (type, dynamic and its rule, on-prem synced, role-assignable, already
        managed by RDG).
    .EXAMPLE
        Invoke-DgApiSearchGroups -Request $Request -Caller $caller -Context $context
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Named after the OpenAPI operationId.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Common handler signature.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [AllowNull()]
        [pscustomobject] $Caller,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $search = Get-DgSearchText -Request $Request
    $graph = Get-DgApiGraph -Context $Context
    $found = Invoke-DgEngine -Name Find-DgDirectoryObject -Parameters @{ Directory = $graph; Kind = 'Group'; Search = $search }
    $data = Get-DgApiStoreData -Context $Context
    $managed = @{}
    foreach ($definition in $data.Definitions) {
        $groupId = Get-DgDefinitionGroupId -Definition $definition -Status $data.Statuses[[string]$definition['id']]
        if ($groupId) { $managed[$groupId] = $definition }
    }
    $items = foreach ($group in $found) {
        $field = { param([string] $Name) Invoke-DgEngine -Name Get-DgFieldValue -Parameters @{ Object = $group; Name = $Name } }
        $id = ([string](& $field 'id')).ToLowerInvariant()
        # Unrolled: a list comes back as one object (see Get-DgDirectoryGroup).
        $types = [string[]]@(@(& $field 'groupTypes') | ForEach-Object { $_ } | Where-Object { $_ })
        $mail = [string](& $field 'mail')
        $rule = [string](& $field 'membershipRule')
        $owner = $managed[$id]
        [ordered]@{
            id                    = $id
            displayName           = [string](& $field 'displayName')
            mail                  = if ($mail) { $mail } else { $null }
            groupType             = Invoke-DgEngine -Name Get-DgGroupKind -Parameters @{ GroupTypes = $types; MailEnabled = [bool](& $field 'mailEnabled'); SecurityEnabled = [bool](& $field 'securityEnabled') }
            memberCount           = $null
            isDynamic             = $types -contains 'DynamicMembership'
            membershipRule        = if ($rule) { $rule } else { $null }
            onPremisesSynced      = [bool](& $field 'onPremisesSyncEnabled')
            isAssignableToRole    = [bool](& $field 'isAssignableToRole')
            managedByDefinitionId = if ($owner) { [string]$owner['id'] } else { $null }
            linkedToName          = if ($owner) { [string]$owner['name'] } else { $null }
        }
    }
    New-DgApiResponse -Status 200 -Body ([ordered]@{ items = [object[]]@($items) })
}
