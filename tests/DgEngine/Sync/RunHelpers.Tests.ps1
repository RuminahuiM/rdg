#Requires -Version 7.4
# The small decisions of a run: due check, settings defaults, names, snapshot fields, timestamps.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force

    function Get-DueReason {
        param([hashtable] $Item = @{}, [string] $Now = '2026-10-12T08:00:00Z', [string] $Mode = 'Scheduled', [string] $DefinitionId)
        $base = @{
            Id = 'def-1'; Enabled = $true; FrequencyMinutes = 15; LastSyncUtc = [DateTimeOffset]'2026-10-12T07:45:00Z'; SyncRequestAt = $null
            Status = [pscustomobject]@{ HandledSyncRequestAt = $null }
        }
        foreach ($key in $Item.Keys) { $base[$key] = $Item[$key] }
        InModuleScope DgEngine -Parameters @{ I = [pscustomobject]$base; N = [DateTimeOffset]$Now; M = $Mode; D = $DefinitionId } {
            Test-DgDefinitionDue -Item $I -Now $N -TickMinutes 3 -Mode $M -DefinitionId $D
        }
    }
}

Describe 'Test-DgDefinitionDue' {
    It 'is due once the interval is over, with one minute of tolerance' {
        Get-DueReason | Should -Be 'Schedule'
        Get-DueReason -Now '2026-10-12T07:59:00Z' | Should -Be 'Schedule'
        Get-DueReason -Now '2026-10-12T07:58:59Z' | Should -BeNullOrEmpty
    }

    It 'raises an interval shorter than the tick to the tick' {
        Get-DueReason -Item @{ FrequencyMinutes = 1; LastSyncUtc = [DateTimeOffset]'2026-10-12T07:59:00Z' } | Should -BeNullOrEmpty
        Get-DueReason -Item @{ FrequencyMinutes = 1; LastSyncUtc = [DateTimeOffset]'2026-10-12T07:58:00Z' } | Should -Be 'Schedule'
    }

    It 'runs a definition that never ran' {
        Get-DueReason -Item @{ LastSyncUtc = $null } | Should -Be 'NeverRun'
    }

    It 'never runs a disabled definition' {
        Get-DueReason -Item @{ Enabled = $false; LastSyncUtc = $null } | Should -BeNullOrEmpty
        Get-DueReason -Item @{ Enabled = $false } -DefinitionId 'def-1' | Should -BeNullOrEmpty
    }

    It 'handles a sync-now request once' {
        $request = [DateTimeOffset]'2026-10-12T07:59:30Z'
        Get-DueReason -Item @{ SyncRequestAt = $request; LastSyncUtc = [DateTimeOffset]'2026-10-12T07:59:00Z' } -Mode SyncNow | Should -Be 'Requested'
        $handled = @{ SyncRequestAt = $request; Status = [pscustomobject]@{ HandledSyncRequestAt = $request } }
        Get-DueReason -Item $handled -Mode SyncNow | Should -BeNullOrEmpty
    }

    It 'takes only requests in SyncNow mode' {
        Get-DueReason -Mode SyncNow | Should -BeNullOrEmpty
    }

    It 'takes the named definition and only that one' {
        Get-DueReason -Item @{ LastSyncUtc = [DateTimeOffset]'2026-10-12T07:59:00Z' } -DefinitionId 'def-1' | Should -Be 'Named'
        Get-DueReason -DefinitionId 'def-2' | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-DgSetting' {
    It 'uses the documented defaults for missing fields' {
        $settings = InModuleScope DgEngine { ConvertTo-DgSetting -Document ([ordered]@{ id = 'settings' }) }
        $settings.ChangeLimitPercent | Should -Be 50
        $settings.ChangeLimitMinChanges | Should -Be 10
        $settings.NewGroupsDryRun | Should -BeTrue
        $settings.NestedMembers | Should -BeTrue
        $settings.Paused | Should -BeFalse
        $settings.Prefix | Should -Be ''
        $settings.MarkerEnabled | Should -BeFalse
    }

    It 'takes prefix and suffix only when enabled' {
        $document = [ordered]@{ naming = [ordered]@{ prefix = [ordered]@{ enabled = $true; text = 'DG-' }; suffix = [ordered]@{ enabled = $false; text = ' (dyn)' } } }
        $settings = InModuleScope DgEngine -Parameters @{ D = $document } { ConvertTo-DgSetting -Document $D }
        $settings.Prefix | Should -Be 'DG-'
        $settings.Suffix | Should -Be ''
    }
}

Describe 'Names' {
    It 'adds prefix and suffix once' {
        InModuleScope DgEngine { Get-DgGroupName -Name 'Sales' -Prefix 'DG-' -Suffix ' (dynamic)' } | Should -Be 'DG-Sales (dynamic)'
        InModuleScope DgEngine { Get-DgGroupName -Name 'DG-Sales (dynamic)' -Prefix 'DG-' -Suffix ' (dynamic)' } | Should -Be 'DG-Sales (dynamic)'
    }

    It 'makes a valid mail nickname from any name' {
        InModuleScope DgEngine { Get-DgMailNickname -Name "Z`u{00FC}rich B`u{00FC}ro (alle)" -Fallback 'rdg-x' } | Should -Be 'Zurich-Buro-alle'
        InModuleScope DgEngine { Get-DgMailNickname -Name '***' -Fallback 'rdg-x' } | Should -Be 'rdg-x'
        (InModuleScope DgEngine { Get-DgMailNickname -Name ('a' * 100) -Fallback 'rdg-x' }).Length | Should -Be 64
    }
}

Describe 'Get-DgSnapshotField' {
    It 'collects the Graph fields of all rules and notices Direct Reports' {
        $fields = InModuleScope DgEngine {
            Get-DgSnapshotField -Rules @('user.department -eq "Sales" -and user.mobile -ne null', 'Direct Reports for "00000000-0000-4000-8000-000000000001"', 'user.extensionAttribute3 -eq "X"')
        }
        ($fields.Select -join ',') | Should -Be 'department,mobilePhone,onPremisesExtensionAttributes'
        $fields.ExpandManager | Should -BeTrue
    }

    It 'skips invalid rules' {
        $fields = InModuleScope DgEngine { Get-DgSnapshotField -Rules @('user.department -eq', 'user.city -eq "Bern"') }
        ($fields.Select -join ',') | Should -Be 'city'
        $fields.ExpandManager | Should -BeFalse
    }
}

Describe 'Timestamps' {
    It 'writes UTC with milliseconds and reads text and parsed dates back' {
        InModuleScope DgEngine { ConvertTo-DgTimestamp -Value ([DateTimeOffset]'2026-10-12T10:00:00+02:00') } | Should -Be '2026-10-12T08:00:00.000Z'
        $fromText = InModuleScope DgEngine { ConvertFrom-DgTimestamp -Value '2026-10-12T08:00:00Z' }
        $fromDate = InModuleScope DgEngine { ConvertFrom-DgTimestamp -Value ([datetime]::SpecifyKind([datetime]'2026-10-12T08:00:00', 'Unspecified')) }
        $fromText.UtcDateTime | Should -Be ([datetime]'2026-10-12T08:00:00')
        $fromDate | Should -Be $fromText
        InModuleScope DgEngine { ConvertFrom-DgTimestamp -Value '' } | Should -BeNullOrEmpty
    }
}
