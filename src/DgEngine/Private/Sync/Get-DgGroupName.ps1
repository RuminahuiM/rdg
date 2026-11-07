function Get-DgGroupName {
    <#
    .SYNOPSIS
        Applies the naming prefix and suffix from Settings to a group name; a name that already
        carries them is returned unchanged, so renaming twice doesn't double them.
    .EXAMPLE
        Get-DgGroupName -Name 'Staff Bern' -Prefix 'DG-'   # DG-Staff Bern
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [string] $Prefix = '',

        [string] $Suffix = ''
    )

    $result = $Name
    if ($Prefix -and -not $result.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $result = $Prefix + $result }
    if ($Suffix -and -not $result.EndsWith($Suffix, [System.StringComparison]::OrdinalIgnoreCase)) { $result = $result + $Suffix }
    $result
}
