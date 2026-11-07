function Get-DgSettingsDocument {
    <#
    .SYNOPSIS
        Reads the settings document, and creates it with the defaults on first use after the
        installation (the API is the only identity that writes the config container).
    .EXAMPLE
        $settings = Get-DgSettingsDocument -Context $Context
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $read = @{ Store = $Context.Store; Container = 'config'; Id = 'settings'; PartitionKey = 'settings' }
    $document = Invoke-DgEngine -Name Get-DgStoreItem -Parameters $read
    if ($document) { return $document }
    # Created at most once: a parallel request that wins the race makes this Add return false.
    $default = Invoke-DgEngine -Name New-DgDefaultSettingDocument
    [void](Invoke-DgEngine -Name Add-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'config'; Document = $default })
    $document = Invoke-DgEngine -Name Get-DgStoreItem -Parameters $read
    if (-not $document) { throw 'the settings document could not be created' }
    $document
}
