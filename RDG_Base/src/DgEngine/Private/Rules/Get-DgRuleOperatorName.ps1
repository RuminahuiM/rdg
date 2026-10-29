function Get-DgRuleOperatorName {
    <#
    .SYNOPSIS
        Returns the canonical name of a rule operator word, or $null if the word isn't one.
    .DESCRIPTION
        The hyphen is optional and case doesn't matter, as in Entra: '-EQ', 'eq' and '-eq' all
        return 'eq'. Canonical names use Entra's spelling, e.g. 'notStartsWith'.
    .EXAMPLE
        Get-DgRuleOperatorName -Word '-StartsWith'   # 'startsWith'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Word
    )

    $operators = @(
        'eq', 'ne', 'startsWith', 'notStartsWith', 'endsWith', 'notEndsWith', 'contains', 'notContains',
        'match', 'notMatch', 'in', 'notIn', 'le', 'ge', 'and', 'or', 'not', 'any', 'all', 'plus', 'minus'
    )
    $name = if ($Word.StartsWith('-')) { $Word.Substring(1) } else { $Word }
    foreach ($operator in $operators) {
        if ($operator -eq $name) {
            # -eq is case-insensitive; return the canonical spelling.
            return $operator
        }
    }
    $null
}
