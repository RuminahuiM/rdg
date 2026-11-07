function Invoke-DgCosmosRequest {
    <#
    .SYNOPSIS
        One Cosmos DB REST call with an Entra token, retried on throttling (429) and on 408/503.
    .DESCRIPTION
        Returns the response (StatusCode, Headers, Content) for every other status; the caller
        decides what a 404, 409 or 412 means.
    .EXAMPLE
        Invoke-DgCosmosRequest -Store $store -Method GET -Path 'dbs/rdg/colls/state/docs/lock-Entra' -PartitionKey 'lock'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Store,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Path,

        [AllowNull()]
        [string] $PartitionKey,

        [hashtable] $Headers = @{},

        [string] $Body
    )

    for ($attempt = 1; ; $attempt++) {
        $now = [DateTimeOffset]::UtcNow
        if (-not $Store.Token -or $Store.Token.ExpiresOn -lt $now.AddMinutes(5)) {
            $Store.Token = if ($Store['ClientId']) {
                Get-DgManagedIdentityToken -Resource $Store.Endpoint -ClientId $Store.ClientId
            } else {
                & $Store.GetToken $Store.Endpoint
            }
        }
        $send = @{
            'Authorization' = [System.Uri]::EscapeDataString("type=aad&ver=1.0&sig=$($Store.Token.Token)")
            'x-ms-date'     = $now.UtcDateTime.ToString('r', [System.Globalization.CultureInfo]::InvariantCulture)
            'x-ms-version'  = '2018-12-31'
            'Accept'        = 'application/json'
        }
        if ($PartitionKey) { $send['x-ms-documentdb-partitionkey'] = ConvertTo-Json -InputObject @($PartitionKey) -Compress }
        if ($Body -and -not $Headers.ContainsKey('Content-Type')) { $send['Content-Type'] = 'application/json' }
        foreach ($key in $Headers.Keys) { $send[$key] = $Headers[$key] }

        $response = & $Store.Request $Method "$($Store.Endpoint)/$Path" $send $Body
        $status = [int]$response.StatusCode
        if ($status -notin @(408, 429, 503) -or $attempt -ge 5) {
            return $response
        }
        $retryMs = 0
        if ($response.Headers -and $response.Headers['x-ms-retry-after-ms']) { $retryMs = [double]$response.Headers['x-ms-retry-after-ms'] }
        $wait = if ($retryMs -gt 0) { [Math]::Min($retryMs / 1000, 60) } else { [Math]::Pow(2, $attempt) }
        Write-DgVerbose -Message "Cosmos DB returned $status; retry $attempt of 4 in $wait s"
        & $Store.Sleep $wait
    }
}
