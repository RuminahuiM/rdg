function New-DgPropertyEntry {
    <#
    .SYNOPSIS
        Creates one row of the rule property map.
    .EXAMPLE
        New-DgPropertyEntry -Name 'city' -Type String -Select 'city' -Read Direct
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('String', 'Boolean', 'Date', 'StringCollection', 'PlanCollection', 'GroupCollection')]
        [string] $Type,

        [AllowNull()]
        [string] $Select,

        [Parameter(Mandatory)]
        [ValidateSet('Direct', 'First', 'Sip', 'Extension')]
        [string] $Read,

        [string] $SubKey
    )

    [pscustomobject]@{
        PSTypeName = 'Dg.PropertyEntry'
        Name       = $Name
        Type       = $Type
        Select     = if ($Select) { $Select } else { $null }
        Read       = $Read
        SubKey     = if ($SubKey) { $SubKey } else { $null }
    }
}
