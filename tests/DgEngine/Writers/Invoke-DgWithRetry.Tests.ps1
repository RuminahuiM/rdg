#Requires -Version 7.4
# Retry, paging and error classification for the directory adapters.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fakes.ps1')
}

Describe 'Invoke-DgGraphRequest' {
    It 'puts the v1.0 base in front of a relative URI' {
        $fake = Get-FakeGraph -Handler { @{ id = 'x' } }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Invoke-DgGraphRequest -Directory $D -Method GET -Uri '/groups/x' }
        $result.id | Should -Be 'x'
        $fake.State.Calls[0].Uri | Should -Be 'https://graph.microsoft.com/v1.0/groups/x'
    }

    It 'keeps an absolute URI as it is' {
        $fake = Get-FakeGraph -Handler { @{} }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { [void](Invoke-DgGraphRequest -Directory $D -Method GET -Uri 'https://graph.microsoft.com/v1.0/users?$skiptoken=a') }
        $fake.State.Calls[0].Uri | Should -Be 'https://graph.microsoft.com/v1.0/users?$skiptoken=a'
    }

    It 'waits as long as Retry-After says after a 429, then retries' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            $Call.State.Attempts++
            if ($Call.State.Attempts -eq 1) { return @{ FakeError = 429; Message = 'Too many requests'; RetryAfter = 7 } }
            @{ id = 'ok' }
        }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Invoke-DgGraphRequest -Directory $D -Method GET -Uri '/x' }
        $result.id | Should -Be 'ok'
        $fake.State.Calls | Should -HaveCount 2
        ($fake.State.Sleeps -join ',') | Should -Be '7'
    }

    It 'backs off 2, 4 seconds on 503 without Retry-After' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            $Call.State.Attempts++
            if ($Call.State.Attempts -le 2) { return @{ FakeError = 503; Message = 'Service unavailable' } }
            @{ id = 'ok' }
        }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { [void](Invoke-DgGraphRequest -Directory $D -Method GET -Uri '/x') }
        ($fake.State.Sleeps -join ',') | Should -Be '2,4'
    }

    It 'caps a very long Retry-After at 120 seconds' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            $Call.State.Attempts++
            if ($Call.State.Attempts -eq 1) { return @{ FakeError = 504; Message = 'Gateway timeout'; RetryAfter = 900 } }
            @{}
        }
        InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { [void](Invoke-DgGraphRequest -Directory $D -Method GET -Uri '/x') }
        ($fake.State.Sleeps -join ',') | Should -Be '120'
    }

    It 'throws a non-transient error at once' {
        $fake = Get-FakeGraph -Handler { @{ FakeError = 400; Message = 'Bad request' } }
        { InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Invoke-DgGraphRequest -Directory $D -Method GET -Uri '/x' } } |
            Should -Throw -ExpectedMessage '*Bad request*'
        $fake.State.Calls | Should -HaveCount 1
        $fake.State.Sleeps | Should -HaveCount 0
    }

    It 'gives up after five attempts' {
        $fake = Get-FakeGraph -Handler { @{ FakeError = 429; Message = 'Too many requests' } }
        { InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Invoke-DgGraphRequest -Directory $D -Method GET -Uri '/x' } } |
            Should -Throw -ExpectedMessage '*429*'
        $fake.State.Calls | Should -HaveCount 5
        ($fake.State.Sleeps -join ',') | Should -Be '2,4,8,16'
    }
}

Describe 'Get-DgGraphCollection' {
    It 'follows nextLink until the last page' {
        $fake = Get-FakeGraph -Handler {
            param($Call)
            switch -Wildcard ($Call.Uri) {
                '*page=2' { @{ value = @(@{ id = 'c' }) } }
                default { @{ value = @(@{ id = 'a' }, @{ id = 'b' }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?page=2' } }
            }
        }
        $items = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { Get-DgGraphCollection -Directory $D -Uri '/users' }
        ($items | ForEach-Object { $_.id }) -join ',' | Should -Be 'a,b,c'
        $fake.State.Calls[1].Uri | Should -Be 'https://graph.microsoft.com/v1.0/users?page=2'
    }

    It 'returns an empty array for an empty collection' {
        $fake = Get-FakeGraph -Handler { @{ value = @() } }
        $items = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } { , (Get-DgGraphCollection -Directory $D -Uri '/users') }
        $items.Count | Should -Be 0
    }
}

Describe 'Get-DgTransientError' {
    It 'treats Exchange throttling messages as transient' {
        $info = InModuleScope DgEngine {
            try { throw [System.InvalidOperationException]::new('The server is busy. Server Busy, try again later') } catch { Get-DgTransientError -ErrorRecord $_ }
        }
        $info.Transient | Should -BeTrue
        $info.Reason | Should -Be 'Exchange throttling'
    }

    It 'reads the status from the exception Data' {
        $info = InModuleScope DgEngine {
            try { throw (New-DgServiceError -StatusCode 404 -Message 'gone') } catch { Get-DgTransientError -ErrorRecord $_ }
        }
        $info.StatusCode | Should -Be 404
        $info.Transient | Should -BeFalse
    }
}

Describe 'Invoke-DgExchangeCommand' {
    It 'retries a throttled cmdlet and passes the parameters through' {
        $fake = Get-FakeExchange -Handler {
            param($Call)
            $Call.State.Attempts++
            if ($Call.State.Attempts -eq 1) { return @{ FakeError = 'exchange'; Message = 'Request was throttled' } }
            "ran $($Call.Command) $($Call.Parameters.Identity)"
        }
        $result = InModuleScope DgEngine -Parameters @{ D = $fake.Directory } {
            Invoke-DgExchangeCommand -Directory $D -Command 'Get-DistributionGroup' -Parameters @{ Identity = 'abc' }
        }
        $result | Should -Be 'ran Get-DistributionGroup abc'
        $fake.State.Sleeps | Should -HaveCount 1
    }
}
