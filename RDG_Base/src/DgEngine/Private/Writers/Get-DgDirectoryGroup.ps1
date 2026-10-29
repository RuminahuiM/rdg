function Get-DgDirectoryGroup {
    <#
    .SYNOPSIS
        Reads one group; $null when it doesn't exist.
    .DESCRIPTION
        Returns Id (Entra object ID), DisplayName, OnPremisesSynced, IsAssignableToRole,
        IsDynamic, MembershipRule, GroupTypes and, for Exchange, Identity (the Exchange GUID
        that cmdlets take).
    .EXAMPLE
        Get-DgDirectoryGroup -Directory $graph -GroupId $id
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [string] $GroupId
    )

    switch ($Directory.Kind) {
        'Custom' { return & $Directory.GetGroup -GroupId $GroupId }
        'Graph' {
            try {
                $group = Invoke-DgGraphRequest -Directory $Directory -Method GET `
                    -Uri "/groups/$GroupId`?`$select=id,displayName,mail,mailEnabled,securityEnabled,groupTypes,onPremisesSyncEnabled,isAssignableToRole,membershipRule"
            } catch {
                if ((Get-DgTransientError -ErrorRecord $_).StatusCode -eq 404) { return $null }
                throw
            }
            # Get-DgFieldValue returns a list as one object; unroll it, or a group with two types
            # (DynamicMembership + Unified) becomes the single string "DynamicMembership Unified".
            $types = [string[]]@(@(Get-DgFieldValue -Object $group -Name 'groupTypes') | ForEach-Object { $_ } | Where-Object { $_ })
            $mailEnabled = [bool](Get-DgFieldValue -Object $group -Name 'mailEnabled')
            $securityEnabled = [bool](Get-DgFieldValue -Object $group -Name 'securityEnabled')
            return [pscustomobject]@{
                Id                 = [string](Get-DgFieldValue -Object $group -Name 'id')
                DisplayName        = [string](Get-DgFieldValue -Object $group -Name 'displayName')
                OnPremisesSynced   = [bool](Get-DgFieldValue -Object $group -Name 'onPremisesSyncEnabled')
                IsAssignableToRole = [bool](Get-DgFieldValue -Object $group -Name 'isAssignableToRole')
                IsDynamic          = $types -contains 'DynamicMembership'
                MembershipRule     = Get-DgFieldValue -Object $group -Name 'membershipRule'
                GroupTypes         = $types
                Identity           = [string](Get-DgFieldValue -Object $group -Name 'id')
                Mail               = [string](Get-DgFieldValue -Object $group -Name 'mail')
                GroupType          = Get-DgGroupKind -GroupTypes $types -MailEnabled $mailEnabled -SecurityEnabled $securityEnabled
            }
        }
        'Exchange' {
            $found = @(Invoke-DgExchangeCommand -Directory $Directory -Command 'Get-DistributionGroup' -Parameters @{
                    Filter = "ExternalDirectoryObjectId -eq '$GroupId'"; ResultSize = 1
                })
            if ($found.Count -eq 0 -or $null -eq $found[0]) { return $null }
            $group = $found[0]
            return [pscustomobject]@{
                Id                 = [string](Get-DgFieldValue -Object $group -Name 'ExternalDirectoryObjectId')
                DisplayName        = [string](Get-DgFieldValue -Object $group -Name 'DisplayName')
                OnPremisesSynced   = [bool](Get-DgFieldValue -Object $group -Name 'IsDirSynced')
                IsAssignableToRole = $false
                IsDynamic          = $false
                MembershipRule     = $null
                GroupTypes         = @()
                Identity           = [string](Get-DgFieldValue -Object $group -Name 'Guid')
                Mail               = [string](Get-DgFieldValue -Object $group -Name 'PrimarySmtpAddress')
                GroupType          = if ([string](Get-DgFieldValue -Object $group -Name 'RecipientTypeDetails') -eq 'MailUniversalSecurityGroup') { 'MailEnabledSecurity' } else { 'Distribution' }
            }
        }
    }
}
