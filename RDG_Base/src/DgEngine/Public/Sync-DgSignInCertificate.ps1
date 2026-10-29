function Sync-DgSignInCertificate {
    <#
    .SYNOPSIS
        Keeps the RDG sign-in app registration's certificates in step with Key Vault: adds the
        newest certificate, removes expired ones, and fails when the newest key is about to expire.
    .DESCRIPTION
        Runs weekly in Renew-SignInCertificate as the "maintenance" identity (owner of the sign-in
        app, Application.ReadWrite.OwnedBy; Key Vault Certificate User on the certificate).
        1. Reads the current certificate version from Key Vault (public part only).
        2. Reads the app's keyCredentials with their key values ($select on a single application).
        3. Keeps every key that hasn't expired, adds the Key Vault certificate if missing, drops
           expired keys; writes keyCredentials once if anything changed. The current key stays,
           so sign-in never breaks.
        4. Fails on purpose when the app's newest key expires within WarnDays (default 21), so
           one alert covers both a broken renewal and a certificate about to lapse.

        Config: ClientId (maintenance identity), KeyVaultUri, CertificateName, SignInAppId.
        Tests pass -Graph and -KeyVault instead.
    .EXAMPLE
        Sync-DgSignInCertificate -Config $config
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [hashtable] $Config,

        [hashtable] $Graph,

        [hashtable] $KeyVault,

        [string] $CertificateName,

        [string] $SignInAppId,

        [Nullable[DateTimeOffset]] $Now,

        [ValidateRange(1, 365)]
        [int] $WarnDays = 21
    )

    if (-not $Config) { $Config = @{} }
    $at = if ($null -ne $Now) { [DateTimeOffset]$Now } else { [DateTimeOffset]::UtcNow }
    if (-not $CertificateName) { $CertificateName = [string]$Config['CertificateName'] }
    if (-not $SignInAppId) { $SignInAppId = [string]$Config['SignInAppId'] }
    if (-not $CertificateName -or -not $SignInAppId) { throw 'CertificateName and SignInAppId are required' }
    if (-not $Graph) {
        if (-not $Config['ClientId']) { throw 'the configuration value ClientId is missing' }
        try {
            Connect-MgGraph -Identity -ClientId ([string]$Config.ClientId) -NoWelcome -ErrorAction Stop | Out-Null
        } catch {
            throw "connecting to Microsoft Graph failed: $($_.Exception.Message)"
        }
        $Graph = New-DgGraphDirectory
    }
    if (-not $KeyVault) {
        if (-not $Config['KeyVaultUri']) { throw 'the configuration value KeyVaultUri is missing' }
        $KeyVault = New-DgKeyVault -VaultUri ([string]$Config.KeyVaultUri) -ClientId ([string]$Config['ClientId'])
    }

    # 1. Key Vault
    $vaultCertificate = Get-DgKeyVaultCertificate -KeyVault $KeyVault -Name $CertificateName

    # 2. The app's keys, with values
    $app = Invoke-DgGraphRequest -Directory $Graph -Method GET -Uri "/applications(appId='$SignInAppId')?`$select=id,keyCredentials"
    $objectId = [string](Get-DgFieldValue -Object $app -Name 'id')
    $existing = [System.Collections.Generic.List[object]]::new()
    foreach ($credential in @(Get-DgFieldValue -Object $app -Name 'keyCredentials')) {
        foreach ($entry in @($credential)) {
            if ($null -eq $entry) { continue }
            $key = [string](Get-DgFieldValue -Object $entry -Name 'key')
            $thumbprint = if ($key) {
                [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Convert]::FromBase64String($key)).Thumbprint
            } else { $null }
            $existing.Add([pscustomobject]@{
                    KeyId      = [string](Get-DgFieldValue -Object $entry -Name 'keyId')
                    Key        = $key
                    Thumbprint = $thumbprint
                    Name       = [string](Get-DgFieldValue -Object $entry -Name 'displayName')
                    Type       = [string](Get-DgFieldValue -Object $entry -Name 'type')
                    Usage      = [string](Get-DgFieldValue -Object $entry -Name 'usage')
                    Start      = ConvertFrom-DgTimestamp -Value (Get-DgFieldValue -Object $entry -Name 'startDateTime')
                    End        = ConvertFrom-DgTimestamp -Value (Get-DgFieldValue -Object $entry -Name 'endDateTime')
                })
        }
    }

    # 3. Keep, add, remove
    $keep = [System.Collections.Generic.List[object]]::new()
    $removed = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $existing) {
        if ($entry.End -and $entry.End -le $at) { $removed.Add($entry) } else { $keep.Add($entry) }
    }
    $added = $null
    $present = @($keep | Where-Object { $_.Thumbprint -eq $vaultCertificate.Thumbprint })
    if ($present.Count -eq 0 -and $vaultCertificate.NotAfter -gt $at) {
        $added = [pscustomobject]@{
            KeyId = $null; Key = $vaultCertificate.Base64; Thumbprint = $vaultCertificate.Thumbprint; Name = $vaultCertificate.Subject
            Type = 'AsymmetricX509Cert'; Usage = 'Verify'; Start = $vaultCertificate.NotBefore; End = $vaultCertificate.NotAfter
        }
        $keep.Add($added)
    }
    foreach ($entry in $keep) {
        if (-not $entry.Key) { throw "the app key $($entry.KeyId) came back without its value; nothing was changed" }
    }

    $changed = $null -ne $added -or $removed.Count -gt 0
    if ($changed) {
        if ($keep.Count -eq 0) { throw 'every key of the sign-in app has expired and Key Vault has no valid certificate; upload a certificate by hand' }
        $body = @{
            keyCredentials = @($keep | ForEach-Object {
                    $credential = [ordered]@{
                        type          = if ($_.Type) { $_.Type } else { 'AsymmetricX509Cert' }
                        usage         = if ($_.Usage) { $_.Usage } else { 'Verify' }
                        key           = $_.Key
                        displayName   = $_.Name
                        startDateTime = ConvertTo-DgTimestamp -Value $_.Start
                        endDateTime   = ConvertTo-DgTimestamp -Value $_.End
                    }
                    if ($_.KeyId) { $credential.keyId = $_.KeyId }
                    $credential
                })
        }
        if ($PSCmdlet.ShouldProcess("sign-in app $SignInAppId", "Update keys (+$([int]($null -ne $added)), -$($removed.Count))")) {
            [void](Invoke-DgGraphRequest -Directory $Graph -Method PATCH -Uri "/applications/$objectId" -Body $body)
        }
    }

    # 4. Newest key must last longer than WarnDays
    $newest = $keep | Sort-Object -Property End -Descending | Select-Object -First 1
    $result = [pscustomobject]@{
        PSTypeName       = 'Dg.CertificateSyncResult'
        Changed          = $changed
        Added            = if ($added) { $added.Thumbprint } else { $null }
        Removed          = [string[]]@($removed | ForEach-Object { if ($_.Thumbprint) { $_.Thumbprint } else { $_.KeyId } })
        NewestThumbprint = if ($newest) { $newest.Thumbprint } else { $null }
        NewestExpires    = if ($newest) { ConvertTo-DgTimestamp -Value $newest.End } else { $null }
    }
    $result
    if (-not $newest -or $newest.End -le $at.AddDays($WarnDays)) {
        $when = if ($newest) { "expires on $(ConvertTo-DgTimestamp -Value $newest.End)" } else { 'is missing' }
        throw "the newest key of the RDG sign-in app $when, within $WarnDays days; check the Key Vault certificate's auto-renewal and this runbook"
    }
}
