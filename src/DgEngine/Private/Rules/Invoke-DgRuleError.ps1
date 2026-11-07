function Invoke-DgRuleError {
    <#
    .SYNOPSIS
        Stops parsing with a rule error.
    .DESCRIPTION
        Throws a FormatException that carries the error object in Exception.Data['DgRuleError'].
        Test-DgRule catches it and returns the error; nothing else should catch it.
    .EXAMPLE
        Invoke-DgRuleError -State $State -Position $token.Position -Message 'expected a value after -eq'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [int] $Position,

        [int] $Length = 1,

        [Parameter(Mandatory)]
        [string] $Message,

        [string] $Suggestion
    )

    $ruleError = New-DgRuleError -Rule $State.Rule -Position $Position -Length $Length -Message $Message -Suggestion $Suggestion
    $exception = [System.FormatException]::new($Message)
    $exception.Data['DgRuleError'] = $ruleError
    throw $exception
}
