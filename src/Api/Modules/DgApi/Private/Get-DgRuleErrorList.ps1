function Get-DgRuleErrorList {
    <#
    .SYNOPSIS
        Turns the engine's rule errors into the API's RuleError objects.
    .EXAMPLE
        Get-DgRuleErrorList -Check (Test-DgRule -Rule $rule)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Check
    )

    foreach ($ruleError in @($Check.Errors)) {
        if ($null -eq $ruleError) { continue }
        $entry = [ordered]@{
            position = [int]$ruleError.Position
            line     = [int]$ruleError.Line
            column   = [int]$ruleError.Column
            length   = [int]$ruleError.Length
            message  = [string]$ruleError.Message
        }
        if ($ruleError.Suggestion) { $entry.suggestion = [string]$ruleError.Suggestion }
        $entry
    }
}
