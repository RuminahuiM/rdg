function New-DgKeyVault {
    <#
    .SYNOPSIS
        Creates the Key Vault client used by the certificate renewal. Reads only public
        certificate data (GET certificates/<name>), with a managed identity token.
    .DESCRIPTION
        Request can be replaced for tests: { param($Path) } -> the parsed JSON response.
    .EXAMPLE
        $vault = New-DgKeyVault -VaultUri 'https://rdg-contoso-kv.vault.azure.net' -ClientId $clientId
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^https://')]
        [string] $VaultUri,

        [string] $ClientId,

        [scriptblock] $Request
    )

    @{
        Kind     = 'KeyVault'
        Uri      = $VaultUri.TrimEnd('/')
        ClientId = $ClientId
        Request  = $Request
    }
}
