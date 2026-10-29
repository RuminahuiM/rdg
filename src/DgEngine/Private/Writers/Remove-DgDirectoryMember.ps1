function Remove-DgDirectoryMember {
    <#
    .SYNOPSIS
        Removes users from a group. Returns Succeeded (IDs) and Failed (Id, Error).
    .DESCRIPTION
        Graph: DELETE .../members/{id}/$ref bundled 20 per $batch; failed entries are retried
        one by one. Exchange: one Remove-DistributionGroupMember per user. "Not a member" (404)
        counts as success. Failures never stop the others.
    .EXAMPLE
        Remove-DgDirectoryMember -Directory $graph -Group $group -UserIds $plan.Removes
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [pscustomobject] $Group,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $UserIds
    )

    $succeeded = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()
    if ($UserIds.Count -eq 0 -or -not $PSCmdlet.ShouldProcess("$($Group.DisplayName) ($($Group.Id))", "Remove $($UserIds.Count) member(s)")) {
        return [pscustomobject]@{ Succeeded = $succeeded.ToArray(); Failed = $failed.ToArray() }
    }

    $notMember = "isn't a member|is not a member|does not exist|couldn't be found"
    $single = {
        param([string] $UserId)
        for ($try = 1; $try -le 2; $try++) {
            try {
                switch ($Directory.Kind) {
                    'Custom' { & $Directory.RemoveMember -Group $Group -UserId $UserId }
                    'Graph' {
                        try {
                            [void](Invoke-DgGraphRequest -Directory $Directory -Method DELETE -Uri "/groups/$($Group.Id)/members/$UserId/`$ref")
                        } catch {
                            if ((Get-DgTransientError -ErrorRecord $_).StatusCode -ne 404) { throw }
                        }
                    }
                    'Exchange' {
                        $recipient = if ($Directory.Recipients -and $Directory.Recipients[$UserId]) { $Directory.Recipients[$UserId] } else { $UserId }
                        [void](Invoke-DgExchangeCommand -Directory $Directory -Command 'Remove-DistributionGroupMember' -Parameters @{
                                Identity = $Group.Identity; Member = $recipient; BypassSecurityGroupManagerCheck = $true; Confirm = $false
                            })
                    }
                }
                $succeeded.Add($UserId)
                return
            } catch {
                if ($_.Exception.Message -match $notMember) { $succeeded.Add($UserId); return }
                if ($try -eq 2) { $failed.Add([pscustomobject]@{ Id = $UserId; Error = $_.Exception.Message }) }
            }
        }
    }

    if ($Directory.Kind -eq 'Graph') {
        for ($i = 0; $i -lt $UserIds.Count; $i += 20) {
            $chunk = [string[]]@($UserIds[$i..([Math]::Min($i + 19, $UserIds.Count - 1))])
            $requests = for ($k = 0; $k -lt $chunk.Count; $k++) {
                @{ id = [string]$k; method = 'DELETE'; url = "/groups/$($Group.Id)/members/$($chunk[$k])/`$ref" }
            }
            $retry = [System.Collections.Generic.List[string]]::new()
            try {
                $response = Invoke-DgGraphRequest -Directory $Directory -Method POST -Uri '/$batch' -Body @{ requests = @($requests) }
                $statuses = @{}
                foreach ($entry in @(Get-DgFieldValue -Object $response -Name 'responses')) {
                    foreach ($item in @($entry)) { $statuses[[string](Get-DgFieldValue -Object $item -Name 'id')] = [int](Get-DgFieldValue -Object $item -Name 'status') }
                }
                for ($k = 0; $k -lt $chunk.Count; $k++) {
                    $status = $statuses[[string]$k]
                    if ($status -in @(200, 204, 404)) { $succeeded.Add($chunk[$k]) } else { $retry.Add($chunk[$k]) }
                }
            } catch {
                foreach ($id in $chunk) { $retry.Add($id) }
            }
            foreach ($id in $retry) { & $single $id }
        }
    } else {
        foreach ($id in $UserIds) { & $single $id }
    }

    [pscustomobject]@{ Succeeded = $succeeded.ToArray(); Failed = $failed.ToArray() }
}
