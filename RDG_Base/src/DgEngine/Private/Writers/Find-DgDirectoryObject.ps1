function Find-DgDirectoryObject {
    <#
    .SYNOPSIS
        Searches users or groups by prefix of display name, UPN (users) or mail, for the pickers.
        Returns up to 25 Graph objects.
    .DESCRIPTION
        Uses startswith filters, which Graph supports without advanced queries. Quotes in the
        search text are escaped for OData.
    .EXAMPLE
        Find-DgDirectoryObject -Directory $graph -Kind User -Search 'ale'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [ValidateSet('User', 'Group')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [ValidateLength(2, 100)]
        [string] $Search
    )

    if ($Directory.Kind -eq 'Custom') {
        $finder = if ($Kind -eq 'User') { $Directory['SearchUsers'] } else { $Directory['SearchGroups'] }
        return , [object[]]@(& $finder -Search $Search)
    }
    $text = $Search.Replace("'", "''")
    if ($Kind -eq 'User') {
        $filter = "startswith(displayName,'$text') or startswith(userPrincipalName,'$text') or startswith(mail,'$text')"
        $select = 'id,displayName,userPrincipalName,mail,accountEnabled,userType'
        $path = '/users'
    } else {
        $filter = "startswith(displayName,'$text') or startswith(mail,'$text')"
        $select = 'id,displayName,mail,mailEnabled,securityEnabled,groupTypes,onPremisesSyncEnabled,isAssignableToRole,membershipRule'
        $path = '/groups'
    }
    $uri = "$path`?`$filter=$([System.Uri]::EscapeDataString($filter))&`$select=$select&`$top=25"
    $page = Invoke-DgGraphRequest -Directory $Directory -Method GET -Uri $uri
    , [object[]]@(@(Get-DgFieldValue -Object $page -Name 'value') | ForEach-Object { $_ } | Where-Object { $null -ne $_ } | Select-Object -First 25)
}
