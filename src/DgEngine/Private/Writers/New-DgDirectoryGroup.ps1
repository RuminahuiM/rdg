function New-DgDirectoryGroup {
    <#
    .SYNOPSIS
        Creates a group and returns it (as Get-DgDirectoryGroup would).
    .DESCRIPTION
        GroupType: Security and Microsoft365 through Graph; MailEnabledSecurity and Distribution
        through Exchange (New-DistributionGroup). Membership is closed for Exchange groups, so
        people can't join or leave on their own. Exchange creates the Entra object a little
        later; the function waits for its object ID (CreateWaitAttempts x 5 s) and fails if it
        doesn't appear, so the definition is retried on the next run instead of creating twice.
    .EXAMPLE
        New-DgDirectoryGroup -Directory $graph -GroupType Security -DisplayName 'DG-Engineering' -MailNickname 'dg-engineering'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [ValidateSet('Security', 'Microsoft365', 'MailEnabledSecurity', 'Distribution')]
        [string] $GroupType,

        [Parameter(Mandatory)]
        [string] $DisplayName,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9._-]{1,64}$')]
        [string] $MailNickname,

        [string] $Description = 'Members managed by RDG (Real Dynamic Groups). Manual changes are reverted.'
    )

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Create $GroupType group")) {
        return $null
    }

    switch ($Directory.Kind) {
        'Custom' {
            return & $Directory.CreateGroup -GroupType $GroupType -DisplayName $DisplayName -MailNickname $MailNickname
        }
        'Graph' {
            $body = switch ($GroupType) {
                'Security' { @{ displayName = $DisplayName; mailNickname = $MailNickname; description = $Description; mailEnabled = $false; securityEnabled = $true } }
                'Microsoft365' { @{ displayName = $DisplayName; mailNickname = $MailNickname; description = $Description; mailEnabled = $true; securityEnabled = $false; groupTypes = @('Unified'); visibility = 'Private' } }
                default { throw "Graph creates Security and Microsoft365 groups only, not $GroupType" }
            }
            $created = Invoke-DgGraphRequest -Directory $Directory -Method POST -Uri '/groups' -Body $body
            return Get-DgDirectoryGroup -Directory $Directory -GroupId ([string](Get-DgFieldValue -Object $created -Name 'id'))
        }
        'Exchange' {
            if ($GroupType -notin @('MailEnabledSecurity', 'Distribution')) {
                throw "Exchange creates MailEnabledSecurity and Distribution groups only, not $GroupType"
            }
            $created = Invoke-DgExchangeCommand -Directory $Directory -Command 'New-DistributionGroup' -Parameters @{
                Name                    = $DisplayName
                DisplayName             = $DisplayName
                Alias                   = $MailNickname
                Type                    = if ($GroupType -eq 'MailEnabledSecurity') { 'Security' } else { 'Distribution' }
                MemberJoinRestriction   = 'Closed'
                MemberDepartRestriction = 'Closed'
                Notes                   = $Description
            }
            $identity = [string](Get-DgFieldValue -Object $created -Name 'Guid')
            $objectId = [string](Get-DgFieldValue -Object $created -Name 'ExternalDirectoryObjectId')
            for ($attempt = 1; -not $objectId -and $attempt -le $Directory.CreateWaitAttempts; $attempt++) {
                & $Directory.Sleep 5
                $again = @(Invoke-DgExchangeCommand -Directory $Directory -Command 'Get-DistributionGroup' -Parameters @{ Identity = $identity })
                if ($again.Count) { $objectId = [string](Get-DgFieldValue -Object $again[0] -Name 'ExternalDirectoryObjectId') }
            }
            if (-not $objectId) {
                throw "the group $DisplayName was created in Exchange (GUID $identity) but has no Entra object ID yet"
            }
            return Get-DgDirectoryGroup -Directory $Directory -GroupId $objectId
        }
    }
}
