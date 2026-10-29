function Read-DgRuleDirectReport {
    <#
    .SYNOPSIS
        Parses 'Direct Reports for "<manager object ID>"', or returns $null if the rule isn't one.
    .DESCRIPTION
        As in Entra, this rule stands alone and can't be combined with other conditions.
    .EXAMPLE
        Read-DgRuleDirectReport -State $state
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $tokens = $State.Tokens
    if ($tokens.Count -lt 4) {
        return $null
    }
    $words = @('Direct', 'Reports', 'for')
    for ($k = 0; $k -lt 3; $k++) {
        if ($tokens[$k].Kind -ne 'Word' -or $tokens[$k].Value -ne $words[$k]) {
            return $null
        }
    }

    $idToken = $tokens[3]
    if ($idToken.Kind -ne 'String') {
        Invoke-DgRuleError -State $State -Position $idToken.Position -Length $idToken.Length `
            -Message 'expected the manager''s object ID in quotes after Direct Reports for'
    }
    $managerId = [guid]::Empty
    if (-not [guid]::TryParse($idToken.Value, [ref]$managerId)) {
        Invoke-DgRuleError -State $State -Position $idToken.Position -Length $idToken.Length `
            -Message "'$($idToken.Value)' is not an object ID (GUID)"
    }
    $next = $tokens[4]
    if ($next.Kind -ne 'End') {
        Invoke-DgRuleError -State $State -Position $next.Position -Length $next.Length `
            -Message 'Direct Reports for can''t be combined with other conditions'
    }

    [pscustomobject]@{
        PSTypeName = 'Dg.RuleNode'
        Kind       = 'DirectReports'
        ManagerId  = $managerId.ToString()
        Position   = $tokens[0].Position
        Length     = $idToken.Position + $idToken.Length - $tokens[0].Position
    }
}
