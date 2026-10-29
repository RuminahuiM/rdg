function Get-DgProvider {
    <#
    .SYNOPSIS
        Which runbook handles a group type: Entra (Security, Microsoft365) or Exchange
        (MailEnabledSecurity, Distribution).
    .EXAMPLE
        Get-DgProvider -GroupType Distribution   # Exchange
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Security', 'Microsoft365', 'MailEnabledSecurity', 'Distribution')]
        [string] $GroupType
    )

    if ($GroupType -in @('Security', 'Microsoft365')) { 'Entra' } else { 'Exchange' }
}
