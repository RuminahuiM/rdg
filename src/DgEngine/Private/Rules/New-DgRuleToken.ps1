function New-DgRuleToken {
    <#
    .SYNOPSIS
        Creates one token of the rule tokenizer.
    .EXAMPLE
        New-DgRuleToken -Kind Word -Text '-eq' -Value '-eq' -Position 16 -Length 3
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('LParen', 'RParen', 'LBracket', 'RBracket', 'Comma', 'String', 'Word', 'End')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [int] $Position,

        [Parameter(Mandatory)]
        [int] $Length
    )

    [pscustomobject]@{
        PSTypeName = 'Dg.RuleToken'
        Kind       = $Kind
        Text       = $Text
        Value      = $Value
        Position   = $Position
        Length     = $Length
    }
}
