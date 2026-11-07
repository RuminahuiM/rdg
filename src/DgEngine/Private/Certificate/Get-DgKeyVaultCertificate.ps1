function Get-DgKeyVaultCertificate {
    <#
    .SYNOPSIS
        Reads the current version of a Key Vault certificate (public part only) and returns it
        as X509Certificate2 plus its base64 DER value.
    .EXAMPLE
        Get-DgKeyVaultCertificate -KeyVault $vault -Name 'rdg-signin'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $KeyVault,

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9A-Za-z-]{1,127}$')]
        [string] $Name
    )

    $path = "/certificates/$Name`?api-version=7.4"
    if ($KeyVault.Request) {
        $response = & $KeyVault.Request $path
    } else {
        if (-not $KeyVault.ClientId) { throw 'the Key Vault client needs the managed identity client ID' }
        $token = Get-DgManagedIdentityToken -Resource 'https://vault.azure.net' -ClientId $KeyVault.ClientId
        $response = Invoke-RestMethod -Method Get -Uri ($KeyVault.Uri + $path) -Headers @{ Authorization = "Bearer $($token.Token)" }
    }
    $cer = [string](Get-DgFieldValue -Object $response -Name 'cer')
    if (-not $cer) { throw "the Key Vault certificate $Name has no public certificate data" }
    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Convert]::FromBase64String($cer))
    [pscustomobject]@{
        Base64      = $cer
        Thumbprint  = $certificate.Thumbprint
        Subject     = $certificate.Subject
        NotBefore   = [DateTimeOffset]$certificate.NotBefore.ToUniversalTime()
        NotAfter    = [DateTimeOffset]$certificate.NotAfter.ToUniversalTime()
        Certificate = $certificate
    }
}
