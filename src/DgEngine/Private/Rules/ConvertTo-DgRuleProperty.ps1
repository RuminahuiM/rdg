function ConvertTo-DgRuleProperty {
    <#
    .SYNOPSIS
        Turns a word into a property reference: user.<name>, or inside -any/-all one of
        _, assignedPlan.<field>, group.<field>.
    .DESCRIPTION
        Only checks the shape. Whether the name exists and which operators fit its type is
        checked by the validator. Names are kept as written; matching is case-insensitive.
    .EXAMPLE
        ConvertTo-DgRuleProperty -State $state -Token $token
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [pscustomobject] $Token
    )

    $text = $Token.Value
    $fail = {
        param([string] $Message)
        Invoke-DgRuleError -State $State -Position $Token.Position -Length $Token.Length -Message $Message
    }

    if (Get-DgRuleOperatorName -Word $text) {
        & $fail "expected a condition$(Get-DgRuleContext -State $State), found $($Token.Text)"
    }

    $object = $null
    $name = $null
    if ($text -eq '_') {
        $object = '_'
        $name = '_'
    } elseif ($text -match '^(?<object>[A-Za-z]+)\.(?<name>[A-Za-z][A-Za-z0-9_]*)$') {
        $object = $Matches['object'].ToLowerInvariant()
        $name = $Matches['name']
    } elseif ($text -match '^[A-Za-z]+\.$') {
        & $fail "missing property name after $text"
    } else {
        & $fail "expected a property like user.department, found $($Token.Text)"
    }

    if ($object -eq 'device') {
        & $fail 'device rules aren''t supported; RDG manages users only'
    }
    if ($object -eq 'system') {
        & $fail "$text can only be used as a value, e.g. user.employeeHireDate -ge system.now"
    }

    if ($State.InCollection) {
        if ($object -eq 'user') {
            & $fail 'inside -any or -all, refer to the item as _, assignedPlan.<field> or group.objectId'
        }
        if ($object -notin @('_', 'assignedplan', 'group')) {
            & $fail "unknown item $text; inside -any or -all use _, assignedPlan.<field> or group.objectId"
        }
        if ($object -eq 'assignedplan') {
            $object = 'assignedPlan'
        }
    } else {
        if ($object -in @('_', 'assignedplan', 'group')) {
            & $fail "$text is only valid inside -any or -all"
        }
        if ($object -ne 'user') {
            & $fail "expected a property like user.department, found $($Token.Text)"
        }
    }

    [pscustomobject]@{
        PSTypeName = 'Dg.RuleProperty'
        Object     = $object
        Name       = $name
        Position   = $Token.Position
        Length     = $Token.Length
    }
}
