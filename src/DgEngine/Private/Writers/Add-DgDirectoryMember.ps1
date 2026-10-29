function Add-DgDirectoryMember {
    <#
    .SYNOPSIS
        Adds users to a group. Returns Succeeded (IDs) and Failed (Id, Error).
    .DESCRIPTION
        Graph: 20 users per PATCH (members@odata.bind). If a batch fails, its users are added one
        by one to find the failing ones. Exchange: one Add-DistributionGroupMember per user, with
        -BypassSecurityGroupManagerCheck. "Already a member" counts as success. Throttling is
        retried; any other failure is retried once, then reported, and never stops the others.
    .EXAMPLE
        Add-DgDirectoryMember -Directory $graph -Group $group -UserIds $plan.Adds
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
    if ($UserIds.Count -eq 0 -or -not $PSCmdlet.ShouldProcess("$($Group.DisplayName) ($($Group.Id))", "Add $($UserIds.Count) member(s)")) {
        return [pscustomobject]@{ Succeeded = $succeeded.ToArray(); Failed = $failed.ToArray() }
    }

    $alreadyMember = 'already exist|already a member|is already a member'
    $single = {
        param([string] $UserId)
        for ($try = 1; $try -le 2; $try++) {
            try {
                switch ($Directory.Kind) {
                    'Custom' { & $Directory.AddMember -Group $Group -UserId $UserId }
                    'Graph' {
                        [void](Invoke-DgGraphRequest -Directory $Directory -Method POST -Uri "/groups/$($Group.Id)/members/`$ref" `
                                -Body @{ '@odata.id' = "$($Directory.BaseUri)/directoryObjects/$UserId" })
                    }
                    'Exchange' {
                        $recipient = if ($Directory.Recipients) { $Directory.Recipients[$UserId] } else { $null }
                        if (-not $recipient) { throw 'the user has no Exchange recipient' }
                        [void](Invoke-DgExchangeCommand -Directory $Directory -Command 'Add-DistributionGroupMember' -Parameters @{
                                Identity = $Group.Identity; Member = $recipient; BypassSecurityGroupManagerCheck = $true; Confirm = $false
                            })
                    }
                }
                $succeeded.Add($UserId)
                return
            } catch {
                if ($_.Exception.Message -match $alreadyMember) { $succeeded.Add($UserId); return }
                if ($try -eq 2) { $failed.Add([pscustomobject]@{ Id = $UserId; Error = $_.Exception.Message }) }
            }
        }
    }

    if ($Directory.Kind -eq 'Graph') {
        for ($i = 0; $i -lt $UserIds.Count; $i += 20) {
            $chunk = [string[]]@($UserIds[$i..([Math]::Min($i + 19, $UserIds.Count - 1))])
            try {
                [void](Invoke-DgGraphRequest -Directory $Directory -Method PATCH -Uri "/groups/$($Group.Id)" -Body @{
                        'members@odata.bind' = [string[]]@($chunk | ForEach-Object { "$($Directory.BaseUri)/directoryObjects/$_" })
                    })
                foreach ($id in $chunk) { $succeeded.Add($id) }
            } catch {
                foreach ($id in $chunk) { & $single $id }
            }
        }
    } else {
        foreach ($id in $UserIds) { & $single $id }
    }

    [pscustomobject]@{ Succeeded = $succeeded.ToArray(); Failed = $failed.ToArray() }
}
