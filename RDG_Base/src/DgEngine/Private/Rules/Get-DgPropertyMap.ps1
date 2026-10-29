# Built once per module load; see Get-DgPropertyMap.
$script:DgPropertyMapCache = $null

function Get-DgPropertyMap {
    <#
    .SYNOPSIS
        Returns the map of rule properties: rule name to type and Graph source.
    .DESCRIPTION
        Keys are rule property names in lower case (rules are case-insensitive). Each entry has:
          Name    - the rule name in Entra's spelling, e.g. 'mailNickName'
          Type    - String, Boolean, Date, StringCollection, PlanCollection, GroupCollection
          Select  - the Graph user field to $select (null for memberOf, resolved separately)
          Read    - how the value is taken from that field: Direct, First (first item),
                    Sip (the SIP: entry of proxyAddresses), Extension (onPremisesExtensionAttributes)
          SubKey  - for Read = Extension, the attribute name inside onPremisesExtensionAttributes
        One row per Entra property (see the Engine design); each row has a test.
        Directory extension properties (extension_<appId>_<name>) aren't in the map; see
        Resolve-DgRuleProperty.
    .EXAMPLE
        (Get-DgPropertyMap)['mailnickname'].Select   # mailNickname
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($null -ne $script:DgPropertyMapCache) {
        return $script:DgPropertyMapCache
    }

    # Leading commas keep each row an array (PowerShell would otherwise flatten them).
    $rows = @(
        , @('accountEnabled', 'Boolean', 'accountEnabled', 'Direct')
        , @('dirSyncEnabled', 'Boolean', 'onPremisesSyncEnabled', 'Direct')
        , @('employeeHireDate', 'Date', 'employeeHireDate', 'Direct')
        , @('objectId', 'String', 'id', 'Direct')
        , @('mailNickName', 'String', 'mailNickname', 'Direct')
        , @('facsimileTelephoneNumber', 'String', 'faxNumber', 'Direct')
        , @('mobile', 'String', 'mobilePhone', 'Direct')
        , @('telephoneNumber', 'String', 'businessPhones', 'First')
        , @('physicalDeliveryOfficeName', 'String', 'officeLocation', 'Direct')
        , @('sipProxyAddress', 'String', 'proxyAddresses', 'Sip')
        , @('otherMails', 'StringCollection', 'otherMails', 'Direct')
        , @('proxyAddresses', 'StringCollection', 'proxyAddresses', 'Direct')
        , @('assignedPlans', 'PlanCollection', 'assignedPlans', 'Direct')
        , @('memberOf', 'GroupCollection', $null, 'Direct')
    )
    $sameName = @(
        'city', 'country', 'companyName', 'department', 'displayName', 'employeeId', 'givenName', 'jobTitle',
        'mail', 'onPremisesDistinguishedName', 'onPremisesSecurityIdentifier', 'passwordPolicies', 'postalCode',
        'preferredLanguage', 'state', 'streetAddress', 'surname', 'usageLocation', 'userPrincipalName', 'userType'
    )

    $map = @{}
    foreach ($row in $rows) {
        $map[$row[0].ToLowerInvariant()] = New-DgPropertyEntry -Name $row[0] -Type $row[1] -Select $row[2] -Read $row[3]
    }
    foreach ($name in $sameName) {
        $map[$name.ToLowerInvariant()] = New-DgPropertyEntry -Name $name -Type 'String' -Select $name -Read 'Direct'
    }
    foreach ($n in 1..15) {
        $name = "extensionAttribute$n"
        $map[$name.ToLowerInvariant()] = New-DgPropertyEntry -Name $name -Type 'String' `
            -Select 'onPremisesExtensionAttributes' -Read 'Extension' -SubKey $name
    }

    $script:DgPropertyMapCache = $map
    $map
}
