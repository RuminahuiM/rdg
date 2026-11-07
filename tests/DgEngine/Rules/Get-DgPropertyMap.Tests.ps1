#Requires -Version 7.4
# One test per row of the property map, as the Engine design asks.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
}

Describe 'Property map' {
    It 'maps <Name> to <Type> from <Select> (<Read>)' -ForEach @(
        @{ Name = 'accountEnabled'; Type = 'Boolean'; Select = 'accountEnabled'; Read = 'Direct' }
        @{ Name = 'dirSyncEnabled'; Type = 'Boolean'; Select = 'onPremisesSyncEnabled'; Read = 'Direct' }
        @{ Name = 'employeeHireDate'; Type = 'Date'; Select = 'employeeHireDate'; Read = 'Direct' }
        @{ Name = 'objectId'; Type = 'String'; Select = 'id'; Read = 'Direct' }
        @{ Name = 'city'; Type = 'String'; Select = 'city'; Read = 'Direct' }
        @{ Name = 'country'; Type = 'String'; Select = 'country'; Read = 'Direct' }
        @{ Name = 'companyName'; Type = 'String'; Select = 'companyName'; Read = 'Direct' }
        @{ Name = 'department'; Type = 'String'; Select = 'department'; Read = 'Direct' }
        @{ Name = 'displayName'; Type = 'String'; Select = 'displayName'; Read = 'Direct' }
        @{ Name = 'employeeId'; Type = 'String'; Select = 'employeeId'; Read = 'Direct' }
        @{ Name = 'givenName'; Type = 'String'; Select = 'givenName'; Read = 'Direct' }
        @{ Name = 'jobTitle'; Type = 'String'; Select = 'jobTitle'; Read = 'Direct' }
        @{ Name = 'mail'; Type = 'String'; Select = 'mail'; Read = 'Direct' }
        @{ Name = 'mailNickName'; Type = 'String'; Select = 'mailNickname'; Read = 'Direct' }
        @{ Name = 'onPremisesDistinguishedName'; Type = 'String'; Select = 'onPremisesDistinguishedName'; Read = 'Direct' }
        @{ Name = 'onPremisesSecurityIdentifier'; Type = 'String'; Select = 'onPremisesSecurityIdentifier'; Read = 'Direct' }
        @{ Name = 'passwordPolicies'; Type = 'String'; Select = 'passwordPolicies'; Read = 'Direct' }
        @{ Name = 'postalCode'; Type = 'String'; Select = 'postalCode'; Read = 'Direct' }
        @{ Name = 'preferredLanguage'; Type = 'String'; Select = 'preferredLanguage'; Read = 'Direct' }
        @{ Name = 'state'; Type = 'String'; Select = 'state'; Read = 'Direct' }
        @{ Name = 'streetAddress'; Type = 'String'; Select = 'streetAddress'; Read = 'Direct' }
        @{ Name = 'surname'; Type = 'String'; Select = 'surname'; Read = 'Direct' }
        @{ Name = 'usageLocation'; Type = 'String'; Select = 'usageLocation'; Read = 'Direct' }
        @{ Name = 'userPrincipalName'; Type = 'String'; Select = 'userPrincipalName'; Read = 'Direct' }
        @{ Name = 'userType'; Type = 'String'; Select = 'userType'; Read = 'Direct' }
        @{ Name = 'facsimileTelephoneNumber'; Type = 'String'; Select = 'faxNumber'; Read = 'Direct' }
        @{ Name = 'mobile'; Type = 'String'; Select = 'mobilePhone'; Read = 'Direct' }
        @{ Name = 'telephoneNumber'; Type = 'String'; Select = 'businessPhones'; Read = 'First' }
        @{ Name = 'physicalDeliveryOfficeName'; Type = 'String'; Select = 'officeLocation'; Read = 'Direct' }
        @{ Name = 'sipProxyAddress'; Type = 'String'; Select = 'proxyAddresses'; Read = 'Sip' }
        @{ Name = 'otherMails'; Type = 'StringCollection'; Select = 'otherMails'; Read = 'Direct' }
        @{ Name = 'proxyAddresses'; Type = 'StringCollection'; Select = 'proxyAddresses'; Read = 'Direct' }
        @{ Name = 'assignedPlans'; Type = 'PlanCollection'; Select = 'assignedPlans'; Read = 'Direct' }
        @{ Name = 'memberOf'; Type = 'GroupCollection'; Select = $null; Read = 'Direct' }
    ) {
        InModuleScope DgEngine -Parameters $_ {
            $entry = Resolve-DgRuleProperty -Name $Name.ToUpperInvariant()
            $entry.Name | Should -BeExactly $Name
            $entry.Type | Should -Be $Type
            $entry.Select | Should -Be $Select
            $entry.Read | Should -Be $Read
        }
    }

    It 'maps extensionAttribute<N> to onPremisesExtensionAttributes' -ForEach @(1..15 | ForEach-Object { @{ N = $_ } }) {
        InModuleScope DgEngine -Parameters @{ N = $N } {
            $entry = Resolve-DgRuleProperty -Name "extensionAttribute$N"
            $entry.Select | Should -Be 'onPremisesExtensionAttributes'
            $entry.Read | Should -Be 'Extension'
            $entry.SubKey | Should -Be "extensionAttribute$N"
        }
    }

    It 'has exactly 49 entries (34 named plus 15 extension attributes)' {
        InModuleScope DgEngine { (Get-DgPropertyMap).Count | Should -Be 49 }
    }

    It 'accepts directory extension properties as text and refuses unknown names' {
        InModuleScope DgEngine {
            (Resolve-DgRuleProperty -Name 'extension_c272a57b722d4eb29bfe327874ae79cb_OfficeNumber').Type | Should -Be 'String'
            Resolve-DgRuleProperty -Name 'extension_short_OfficeNumber' | Should -BeNullOrEmpty
            Resolve-DgRuleProperty -Name 'favouriteColour' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-DgUserValue' {
    It 'reads <Name> from a hashtable user' -ForEach @(
        @{ Name = 'department'; Expected = 'Sales' }
        @{ Name = 'telephoneNumber'; Expected = '+41 31 000 00 01' }
        @{ Name = 'sipProxyAddress'; Expected = 'alex@contoso.org' }
        @{ Name = 'extensionAttribute3'; Expected = 'OPS' }
        @{ Name = 'objectId'; Expected = '11111111-1111-4111-8111-111111111111' }
    ) {
        InModuleScope DgEngine -Parameters $_ {
            $user = @{
                id                            = '11111111-1111-4111-8111-111111111111'
                department                    = 'Sales'
                businessPhones                = @('+41 31 000 00 01', '+41 31 000 00 02')
                proxyAddresses                = @('SMTP:alex@contoso.org', 'sip:alex@contoso.org')
                onPremisesExtensionAttributes = @{ extensionAttribute3 = 'OPS' }
            }
            Get-DgUserValue -User $user -Entry (Resolve-DgRuleProperty -Name $Name) | Should -Be $Expected
        }
    }

    It 'returns null for missing fields and works with objects too' {
        InModuleScope DgEngine {
            $user = [pscustomobject]@{ city = 'Bern' }
            Get-DgUserValue -User $user -Entry (Resolve-DgRuleProperty -Name 'city') | Should -Be 'Bern'
            Get-DgUserValue -User $user -Entry (Resolve-DgRuleProperty -Name 'extensionAttribute1') | Should -BeNullOrEmpty
            Get-DgUserValue -User $user -Entry (Resolve-DgRuleProperty -Name 'telephoneNumber') | Should -BeNullOrEmpty
        }
    }
}
