function Get-DgMailNickname {
    <#
    .SYNOPSIS
        Makes a mail nickname (alias) from a group name when the definition doesn't set one:
        letters, digits, dot, dash and underscore only, at most 64 characters.
    .EXAMPLE
        Get-DgMailNickname -Name 'Staff Bern (all)' -Fallback 'rdg-01J'   # Staff-Bern-all
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Fallback
    )

    $plain = $Name.Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $alias = ($plain -replace '[^A-Za-z0-9._-]+', '-').Trim('-', '.')
    if ($alias.Length -gt 64) { $alias = $alias.Substring(0, 64).Trim('-', '.') }
    if (-not $alias) { $alias = $Fallback }
    $alias
}
