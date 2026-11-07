function Select-DgImplicitFilter {
    <#
    .SYNOPSIS
        Drops disabled accounts and guests from a rule result, unless the definition includes them.
    .DESCRIPTION
        Returns Kept (users that stay) and Excluded (user plus reason). A user who is both
        disabled and a guest counts once, as disabled. Users added through the definition's
        include list are not passed through here: an explicit include bypasses the filters.
        The snapshot must always load accountEnabled and userType: a missing accountEnabled
        counts as enabled and a missing userType as a member, so leaving them out would let
        disabled accounts and guests through.
    .EXAMPLE
        Select-DgImplicitFilter -Users $matched -IncludeDisabled:$false -IncludeGuests:$false
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Users,

        [switch] $IncludeDisabled,

        [switch] $IncludeGuests
    )

    $kept = [System.Collections.Generic.List[object]]::new()
    $excluded = [System.Collections.Generic.List[object]]::new()
    $disabled = 0
    $guests = 0
    foreach ($user in $Users) {
        $enabled = Get-DgFieldValue -Object $user -Name 'accountEnabled'
        $userType = [string](Get-DgFieldValue -Object $user -Name 'userType')
        if (-not $IncludeDisabled -and $enabled -eq $false) {
            $excluded.Add([pscustomobject]@{ User = $user; Reason = 'disabled' })
            $disabled++
        } elseif (-not $IncludeGuests -and $userType -eq 'Guest') {
            $excluded.Add([pscustomobject]@{ User = $user; Reason = 'guest' })
            $guests++
        } else {
            $kept.Add($user)
        }
    }

    [pscustomobject]@{
        PSTypeName = 'Dg.FilterResult'
        Kept       = $kept.ToArray()
        Excluded   = $excluded.ToArray()
        Counts     = [pscustomobject]@{ Disabled = $disabled; Guests = $guests }
    }
}
