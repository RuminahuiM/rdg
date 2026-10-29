#Requires -Version 7.4
# The Cosmos DB store client against a fake REST endpoint, and the run lock on the in-memory store.

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force

    # A fake Cosmos endpoint: $Handler gets one $Call (Method, Uri, Headers, Body, State) and
    # returns @{ StatusCode; Headers; Content }. Calls, waits and token requests are recorded.
    function Get-FakeCosmosEndpoint {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'GetToken interface parameter.')]
        param([scriptblock] $Handler)
        $state = @{
            Calls    = [System.Collections.Generic.List[object]]::new()
            Sleeps   = [System.Collections.Generic.List[double]]::new()
            Tokens   = 0
            Attempts = 0
            Handler  = $Handler
        }
        $store = InModuleScope DgEngine { New-DgCosmosStore -Endpoint 'https://rdg-contoso.documents.azure.com/' -Database 'rdg' }
        $store.Request = {
            param($Method, $Uri, $Headers, $Body)
            $call = [pscustomobject]@{ Method = $Method; Uri = $Uri; Headers = $Headers; Body = $Body; State = $state }
            $state.Calls.Add($call)
            & $state.Handler $call
        }.GetNewClosure()
        $store.GetToken = { param($Resource) $state.Tokens++; @{ Token = "token-$($state.Tokens)"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1) } }.GetNewClosure()
        $store.Sleep = { param($Seconds) $state.Sleeps.Add($Seconds) }.GetNewClosure()
        @{ Store = $store; State = $state }
    }
}

Describe 'Cosmos DB store client' {
    It 'uses scheme and host only as endpoint and token audience (Azure reports :443/)' {
        $store = InModuleScope DgEngine { New-DgCosmosStore -Endpoint 'https://rdg-contoso.documents.azure.com:443/' -Database 'rdg' }
        $store.Endpoint | Should -Be 'https://rdg-contoso.documents.azure.com'
    }

    It 'reads a document with an Entra token, the API version and the partition key' {
        $fake = Get-FakeCosmosEndpoint -Handler { @{ StatusCode = 200; Headers = @{}; Content = '{"id":"lock-Entra","pk":"lock","_etag":"\"e1\""}' } }
        $doc = InModuleScope DgEngine -Parameters @{ S = $fake.Store } { Get-DgStoreItem -Store $S -Container state -Id 'lock-Entra' -PartitionKey 'lock' }
        $doc['_etag'] | Should -Be '"e1"'
        $call = $fake.State.Calls[0]
        $call.Method | Should -Be 'GET'
        $call.Uri | Should -Be 'https://rdg-contoso.documents.azure.com/dbs/rdg/colls/state/docs/lock-Entra'
        $call.Headers['Authorization'] | Should -Be 'type%3Daad%26ver%3D1.0%26sig%3Dtoken-1'
        $call.Headers['x-ms-version'] | Should -Be '2018-12-31'
        $call.Headers['x-ms-documentdb-partitionkey'] | Should -Be '["lock"]'
        $call.Headers['x-ms-date'] | Should -BeLike '*GMT'
    }

    It 'returns nothing for a missing document and reuses the token' {
        $fake = Get-FakeCosmosEndpoint -Handler { @{ StatusCode = 404; Headers = @{}; Content = '{"code":"NotFound"}' } }
        $bothMissing = InModuleScope DgEngine -Parameters @{ S = $fake.Store } {
            $a = Get-DgStoreItem -Store $S -Container state -Id 'a' -PartitionKey 'p'
            $b = Get-DgStoreItem -Store $S -Container state -Id 'b' -PartitionKey 'p'
            $null -eq $a -and $null -eq $b
        }
        $bothMissing | Should -BeTrue
        $fake.State.Tokens | Should -Be 1
    }

    It 'throws other errors with the status code' {
        $fake = Get-FakeCosmosEndpoint -Handler { @{ StatusCode = 403; Headers = @{}; Content = '{"code":"Forbidden","message":"missing role"}' } }
        { InModuleScope DgEngine -Parameters @{ S = $fake.Store } { Get-DgStoreItem -Store $S -Container config -Id 'settings' -PartitionKey 'settings' } } |
            Should -Throw -ExpectedMessage '*403*missing role*'
    }

    It 'waits as long as Cosmos DB says on 429, then retries' {
        $fake = Get-FakeCosmosEndpoint -Handler {
            param($Call)
            $Call.State.Attempts++
            if ($Call.State.Attempts -eq 1) { return @{ StatusCode = 429; Headers = @{ 'x-ms-retry-after-ms' = '1500' }; Content = '' } }
            @{ StatusCode = 200; Headers = @{}; Content = '{"id":"x"}' }
        }
        $doc = InModuleScope DgEngine -Parameters @{ S = $fake.Store } { Get-DgStoreItem -Store $S -Container state -Id 'x' -PartitionKey 'x' }
        $doc['id'] | Should -Be 'x'
        ($fake.State.Sleeps -join ',') | Should -Be '1.5'
    }

    It 'creates with POST and reports a conflict as false' {
        $fake = Get-FakeCosmosEndpoint -Handler {
            param($Call)
            $Call.State.Attempts++
            if ($Call.State.Attempts -eq 1) { @{ StatusCode = 201; Headers = @{}; Content = '{}' } } else { @{ StatusCode = 409; Headers = @{}; Content = '{}' } }
        }
        $results = InModuleScope DgEngine -Parameters @{ S = $fake.Store } {
            $doc = [ordered]@{ id = 'lock-Entra'; pk = 'lock'; type = 'lock' }
            Add-DgStoreItem -Store $S -Container state -Document $doc
            Add-DgStoreItem -Store $S -Container state -Document $doc
        }
        ($results -join ',') | Should -Be 'True,False'
        $fake.State.Calls[0].Method | Should -Be 'POST'
        $fake.State.Calls[0].Headers.ContainsKey('x-ms-documentdb-is-upsert') | Should -BeFalse
        ($fake.State.Calls[0].Body | ConvertFrom-Json).id | Should -Be 'lock-Entra'
    }

    It 'upserts without an ETag, and drops the Cosmos system fields' {
        $fake = Get-FakeCosmosEndpoint -Handler { @{ StatusCode = 200; Headers = @{}; Content = '{}' } }
        InModuleScope DgEngine -Parameters @{ S = $fake.Store } {
            [void](Set-DgStoreItem -Store $S -Container state -Document ([ordered]@{ id = 'status-x'; pk = 'def-x'; _etag = '"old"'; _ts = 5; _rid = 'r' }))
        }
        $call = $fake.State.Calls[0]
        $call.Headers['x-ms-documentdb-is-upsert'] | Should -Be 'True'
        $call.Headers['x-ms-documentdb-partitionkey'] | Should -Be '["def-x"]'
        $call.Body | Should -Not -BeLike '*_etag*'
        $call.Body | Should -Not -BeLike '*_ts*'
    }

    It 'replaces with If-Match and reports a lost race as false' {
        $fake = Get-FakeCosmosEndpoint -Handler { @{ StatusCode = 412; Headers = @{}; Content = '{}' } }
        $ok = InModuleScope DgEngine -Parameters @{ S = $fake.Store } {
            Set-DgStoreItem -Store $S -Container state -Document ([ordered]@{ id = 'lock-Entra'; pk = 'lock' }) -ETag '"e1"'
        }
        $ok | Should -BeFalse
        $fake.State.Calls[0].Method | Should -Be 'PUT'
        $fake.State.Calls[0].Headers['If-Match'] | Should -Be '"e1"'
        $fake.State.Calls[0].Uri | Should -BeLike '*/docs/lock-Entra'
    }

    It 'deletes with If-Match; a missing document counts as deleted' {
        $fake = Get-FakeCosmosEndpoint -Handler {
            param($Call)
            $Call.State.Attempts++
            @{ StatusCode = @(204, 404, 412)[$Call.State.Attempts - 1]; Headers = @{}; Content = '' }
        }
        $results = InModuleScope DgEngine -Parameters @{ S = $fake.Store } {
            1..3 | ForEach-Object { Remove-DgStoreItem -Store $S -Container state -Id 'lock-Entra' -PartitionKey 'lock' -ETag '"e1"' }
        }
        ($results -join ',') | Should -Be 'True,True,False'
        $fake.State.Calls[0].Method | Should -Be 'DELETE'
    }

    It 'queries across partitions and follows the continuation token' {
        $fake = Get-FakeCosmosEndpoint -Handler {
            param($Call)
            if ($Call.Headers['x-ms-continuation'] -eq 'page2') {
                return @{ StatusCode = 200; Headers = @{}; Content = '{"Documents":[{"id":"c"}]}' }
            }
            @{ StatusCode = 200; Headers = @{ 'x-ms-continuation' = 'page2' }; Content = '{"Documents":[{"id":"a"},{"id":"b"}]}' }
        }
        $items = InModuleScope DgEngine -Parameters @{ S = $fake.Store } { Find-DgStoreItem -Store $S -Container config -Type definition }
        ($items | ForEach-Object { $_['id'] }) -join ',' | Should -Be 'a,b,c'
        $call = $fake.State.Calls[0]
        $call.Headers['Content-Type'] | Should -Be 'application/query+json'
        $call.Headers['x-ms-documentdb-isquery'] | Should -Be 'True'
        $call.Headers['x-ms-documentdb-query-enablecrosspartition'] | Should -Be 'True'
        $query = $call.Body | ConvertFrom-Json
        $query.query | Should -Be 'SELECT * FROM c WHERE c.type = @type'
        $query.parameters[0].value | Should -Be 'definition'
    }
}

Describe 'Invoke-DgStoreBatch' {
    It 'sends an atomic batch with the partition key and operations, and reads a failed operation''s status' {
        $fake = Get-FakeCosmosEndpoint -Handler {
            param($Call)
            $Call.State.Attempts++
            if ($Call.State.Attempts -eq 1) { return @{ StatusCode = 200; Headers = @{}; Content = '[{"statusCode":200},{"statusCode":201}]' } }
            @{ StatusCode = 412; Headers = @{}; Content = '[{"statusCode":412},{"statusCode":424}]' }
        }
        $results = InModuleScope DgEngine -Parameters @{ S = $fake.Store } {
            $operations = @(
                @{ Kind = 'Replace'; Document = [ordered]@{ id = 'def-1'; pk = 'def-1'; _etag = '"x"' }; IfMatch = '"e1"' }
                @{ Kind = 'Create'; Document = [ordered]@{ id = 'aud-1'; pk = 'def-1' } }
            )
            Invoke-DgStoreBatch -Store $S -Container config -PartitionKey 'def-1' -Operations $operations
            Invoke-DgStoreBatch -Store $S -Container config -PartitionKey 'def-1' -Operations $operations
        }
        $results[0].Succeeded | Should -BeTrue
        $results[1].Succeeded | Should -BeFalse
        $results[1].Status | Should -Be 412
        $results[1].FailedIndex | Should -Be 0
        $call = $fake.State.Calls[0]
        $call.Headers['x-ms-cosmos-is-batch-request'] | Should -Be 'True'
        $call.Headers['x-ms-cosmos-batch-atomic'] | Should -Be 'True'
        $call.Headers['x-ms-documentdb-partitionkey'] | Should -Be '["def-1"]'
        $body = $call.Body | ConvertFrom-Json
        $body[0].operationType | Should -Be 'Replace'
        $body[0].id | Should -Be 'def-1'
        $body[0].ifMatch | Should -Be '"e1"'
        $body[0].resourceBody.PSObject.Properties['_etag'] | Should -BeNullOrEmpty
        $body[1].operationType | Should -Be 'Create'
    }

    It 'applies all or nothing in the memory store' {
        $result = InModuleScope DgEngine {
            $store = New-DgMemoryStore
            [void](Set-DgStoreItem -Store $store -Container config -Document ([ordered]@{ id = 'def-1'; pk = 'def-1'; type = 'definition'; name = 'a' }))
            $etag = (Get-DgStoreItem -Store $store -Container config -Id 'def-1' -PartitionKey 'def-1')['_etag']
            $conflict = Invoke-DgStoreBatch -Store $store -Container config -PartitionKey 'def-1' -Operations @(
                @{ Kind = 'Create'; Document = [ordered]@{ id = 'aud-1'; pk = 'def-1'; type = 'audit' } }
                @{ Kind = 'Replace'; Document = [ordered]@{ id = 'def-1'; pk = 'def-1'; type = 'definition'; name = 'b' }; IfMatch = '"stale"' }
            )
            $afterConflict = (Find-DgStoreItem -Store $store -Container config -Type audit).Count
            $ok = Invoke-DgStoreBatch -Store $store -Container config -PartitionKey 'def-1' -Operations @(
                @{ Kind = 'Replace'; Document = [ordered]@{ id = 'def-1'; pk = 'def-1'; type = 'definition'; name = 'b' }; IfMatch = $etag }
                @{ Kind = 'Create'; Document = [ordered]@{ id = 'aud-1'; pk = 'def-1'; type = 'audit' } }
            )
            $duplicate = Invoke-DgStoreBatch -Store $store -Container config -PartitionKey 'def-1' -Operations @(@{ Kind = 'Create'; Document = [ordered]@{ id = 'aud-1'; pk = 'def-1'; type = 'audit' } })
            $deleted = Invoke-DgStoreBatch -Store $store -Container config -PartitionKey 'def-1' -Operations @(@{ Kind = 'Delete'; Id = 'def-1' })
            $wrongPartition = try { [void](Invoke-DgStoreBatch -Store $store -Container config -PartitionKey 'def-1' -Operations @(@{ Kind = 'Create'; Document = [ordered]@{ id = 'x'; pk = 'def-2' } })); 'written' } catch { 'refused' }
            [pscustomobject]@{
                Conflict = $conflict.Status; AfterConflict = $afterConflict; Ok = $ok.Succeeded; Name = (Get-DgStoreItem -Store $store -Container config -Id 'def-1' -PartitionKey 'def-1')
                Duplicate = $duplicate.Status; Deleted = $deleted.Succeeded; WrongPartition = $wrongPartition
            }
        }
        $result.Conflict | Should -Be 412
        $result.AfterConflict | Should -Be 0
        $result.Ok | Should -BeTrue
        $result.Duplicate | Should -Be 409
        $result.Deleted | Should -BeTrue
        $result.Name | Should -BeNullOrEmpty
        $result.WrongPartition | Should -Be 'refused'
    }
}

Describe 'Run lock' {
    It 'is taken once; a second job sees who holds it; release frees it' {
        $result = InModuleScope DgEngine {
            $store = New-DgMemoryStore
            $now = [DateTimeOffset]'2026-10-12T08:00:00Z'
            $first = Enter-DgRunLock -Store $store -Provider Entra -JobId 'job-a' -Now $now -LeaseMinutes 6
            $second = Enter-DgRunLock -Store $store -Provider Entra -JobId 'job-b' -Now $now.AddMinutes(1) -LeaseMinutes 6
            $released = Exit-DgRunLock -Store $store -Lock $first.Lock
            $third = Enter-DgRunLock -Store $store -Provider Entra -JobId 'job-c' -Now $now.AddMinutes(2) -LeaseMinutes 6
            [pscustomobject]@{ First = $first.Acquired; Second = $second.Acquired; HeldBy = $second.HeldBy; Released = $released; Third = $third.Acquired }
        }
        $result.First | Should -BeTrue
        $result.Second | Should -BeFalse
        $result.HeldBy | Should -Be 'job-a'
        $result.Released | Should -BeTrue
        $result.Third | Should -BeTrue
    }

    It 'takes over an expired lease, and the crashed job cannot release the new holder''s lock' {
        $result = InModuleScope DgEngine {
            $store = New-DgMemoryStore
            $now = [DateTimeOffset]'2026-10-12T08:00:00Z'
            $crashed = Enter-DgRunLock -Store $store -Provider Exchange -JobId 'job-a' -Now $now -LeaseMinutes 6
            $next = Enter-DgRunLock -Store $store -Provider Exchange -JobId 'job-b' -Now $now.AddMinutes(7) -LeaseMinutes 6
            $lateRelease = Exit-DgRunLock -Store $store -Lock $crashed.Lock
            $stored = Get-DgStoreItem -Store $store -Container state -Id 'lock-Exchange' -PartitionKey 'lock'
            [pscustomobject]@{ Next = $next.Acquired; LateRelease = $lateRelease; Holder = $stored['jobId'] }
        }
        $result.Next | Should -BeTrue
        $result.LateRelease | Should -BeFalse
        $result.Holder | Should -Be 'job-b'
    }

    It 'lets only one of two jobs replace the same expired lease' {
        $result = InModuleScope DgEngine {
            $store = New-DgMemoryStore
            $now = [DateTimeOffset]'2026-10-12T08:00:00Z'
            [void](Enter-DgRunLock -Store $store -Provider Entra -JobId 'job-a' -Now $now -LeaseMinutes 6)
            # Both jobs read the expired lock; job-b replaces it first.
            $seen = Get-DgStoreItem -Store $store -Container state -Id 'lock-Entra' -PartitionKey 'lock'
            $winner = Enter-DgRunLock -Store $store -Provider Entra -JobId 'job-b' -Now $now.AddMinutes(7) -LeaseMinutes 6
            $seen['jobId'] = 'job-c'
            $loser = Set-DgStoreItem -Store $store -Container state -Document $seen -ETag $seen['_etag']
            [pscustomobject]@{ Winner = $winner.Acquired; Loser = $loser; Holder = (Get-DgStoreItem -Store $store -Container state -Id 'lock-Entra' -PartitionKey 'lock')['jobId'] }
        }
        $result.Winner | Should -BeTrue
        $result.Loser | Should -BeFalse
        $result.Holder | Should -Be 'job-b'
    }

    It 'keeps the two runbooks apart' {
        $result = InModuleScope DgEngine {
            $store = New-DgMemoryStore
            $now = [DateTimeOffset]'2026-10-12T08:00:00Z'
            $entra = Enter-DgRunLock -Store $store -Provider Entra -JobId 'job-a' -Now $now -LeaseMinutes 6
            $exchange = Enter-DgRunLock -Store $store -Provider Exchange -JobId 'job-b' -Now $now -LeaseMinutes 6
            $entra.Acquired -and $exchange.Acquired
        }
        $result | Should -BeTrue
    }
}
