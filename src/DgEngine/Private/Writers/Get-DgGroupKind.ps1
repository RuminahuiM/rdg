function Get-DgGroupKind {
    <#
    .SYNOPSIS
        Names a Graph group's type the way RDG does: Microsoft365, Security, MailEnabledSecurity,
        Distribution, or Other.
    .EXAMPLE
        Get-DgGroupKind -GroupTypes @('Unified') -MailEnabled $true -SecurityEnabled $false   # Microsoft365
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()]
        [string[]] $GroupTypes = @(),

        [bool] $MailEnabled,

        [bool] $SecurityEnabled
    )

    if ($GroupTypes -contains 'Unified') { return 'Microsoft365' }
    if ($SecurityEnabled -and -not $MailEnabled) { return 'Security' }
    if ($SecurityEnabled -and $MailEnabled) { return 'MailEnabledSecurity' }
    if ($MailEnabled) { return 'Distribution' }
    'Other'
}
