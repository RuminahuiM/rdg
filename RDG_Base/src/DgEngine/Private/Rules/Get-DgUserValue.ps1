function Get-DgUserValue {
    <#
    .SYNOPSIS
        Reads a rule property's value from a Graph user record; $null when it is missing.
    .DESCRIPTION
        Users come from the snapshot as hashtables (Invoke-MgGraphRequest -OutputType Hashtable)
        or as objects; both work. Field names are Graph's.
    .EXAMPLE
        Get-DgUserValue -User $user -Entry (Resolve-DgRuleProperty -Name 'extensionAttribute3')
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object] $User,

        [Parameter(Mandatory)]
        [pscustomobject] $Entry
    )

    $raw = Get-DgFieldValue -Object $User -Name $Entry.Select
    switch ($Entry.Read) {
        'Direct' {
            return , $raw
        }
        'First' {
            $items = @($raw | Where-Object { $null -ne $_ })
            if ($items.Count) { return $items[0] }
            return $null
        }
        'Sip' {
            foreach ($address in @($raw)) {
                if ($address -is [string] -and $address.StartsWith('sip:', [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $address.Substring(4)
                }
            }
            return $null
        }
        'Extension' {
            if ($null -eq $raw) { return $null }
            return Get-DgFieldValue -Object $raw -Name $Entry.SubKey
        }
    }
}
