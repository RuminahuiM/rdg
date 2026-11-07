# Test doubles for the directory adapters. Dot-source in BeforeAll.
#
# A handler gets one $Call object: Method, Uri, Body, State for Graph or Command, Parameters, State
# for Exchange (State is the shared fake state, with an Attempts counter for stateful doubles).
# It returns the response. To simulate a failure it returns @{ FakeError = <status>;
# Message = '...'; RetryAfter = <seconds> } (Graph) or @{ FakeError = 'exchange'; Message = '...' }.
# Every call is recorded in $fake.State.Calls and every wait in $fake.State.Sleeps.

function Get-FakeGraph {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Handler,

        [string] $MarkerExtension
    )
    $state = @{
        Calls    = [System.Collections.Generic.List[object]]::new()
        Sleeps   = [System.Collections.Generic.List[double]]::new()
        Handler  = $Handler
        Attempts = 0
    }
    $directory = @{
        Kind            = 'Graph'
        BaseUri         = 'https://graph.microsoft.com/v1.0'
        MarkerExtension = $MarkerExtension
        Request         = {
            param([string] $Method, [string] $Uri, [object] $Body)
            $state.Calls.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body })
            $response = & $state.Handler ([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body; State = $state })
            if ($response -is [hashtable] -and $response.ContainsKey('FakeError')) {
                $exception = [System.Net.Http.HttpRequestException]::new("HTTP $($response.FakeError): $($response.Message)")
                $exception.Data['StatusCode'] = $response.FakeError
                $exception.Data['RetryAfter'] = if ($response.ContainsKey('RetryAfter')) { $response.RetryAfter } else { 0 }
                throw $exception
            }
            $response
        }.GetNewClosure()
        Sleep           = { param([double] $Seconds) $state.Sleeps.Add($Seconds) }.GetNewClosure()
    }
    @{ Directory = $directory; State = $state }
}

function Get-FakeExchange {
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Handler,

        [int] $MarkerAttribute = 0,

        [int] $CreateWaitAttempts = 3
    )
    $state = @{
        Calls    = [System.Collections.Generic.List[object]]::new()
        Sleeps   = [System.Collections.Generic.List[double]]::new()
        Handler  = $Handler
        Attempts = 0
    }
    $directory = @{
        Kind               = 'Exchange'
        MarkerAttribute    = $MarkerAttribute
        CreateWaitAttempts = $CreateWaitAttempts
        Recipients         = $null
        Invoke             = {
            param([string] $Command, [hashtable] $Parameters)
            $state.Calls.Add([pscustomobject]@{ Command = $Command; Parameters = $Parameters })
            $response = & $state.Handler ([pscustomobject]@{ Command = $Command; Parameters = $Parameters; State = $state })
            if ($response -is [hashtable] -and $response.ContainsKey('FakeError')) {
                throw [System.InvalidOperationException]::new($response.Message)
            }
            $response
        }.GetNewClosure()
        Sleep              = { param([double] $Seconds) $state.Sleeps.Add($Seconds) }.GetNewClosure()
    }
    @{ Directory = $directory; State = $state }
}

function Get-TestGroup {
    param([string] $Id = 'g1', [bool] $IsDynamic = $false, [string[]] $GroupTypes = @())
    [pscustomobject]@{
        Id = $Id; DisplayName = "Group $Id"; Identity = "guid-$Id"; IsDynamic = $IsDynamic; GroupTypes = $GroupTypes
        OnPremisesSynced = $false; IsAssignableToRole = $false; MembershipRule = $null
    }
}
