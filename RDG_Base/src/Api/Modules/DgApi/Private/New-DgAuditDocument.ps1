function New-DgAuditDocument {
    <#
    .SYNOPSIS
        Builds an audit record for a change: same partition as the changed document, kept for the
        audit retention setting (ttl).
    .EXAMPLE
        New-DgAuditDocument -Context $Context -PartitionKey $id -Action update -By $caller.Upn -Changes $changes -DefinitionName $name
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory object only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Context,

        [Parameter(Mandatory)]
        [string] $PartitionKey,

        [Parameter(Mandatory)]
        [ValidateSet('create', 'update', 'delete', 'adopt', 'approve', 'syncNow', 'settings')]
        [string] $Action,

        [Parameter(Mandatory)]
        [string] $By,

        [AllowEmptyCollection()]
        [object[]] $Changes = @(),

        [string] $DefinitionName
    )

    $settings = Invoke-DgEngine -Name Get-DgStoreItem -Parameters @{ Store = $Context.Store; Container = 'config'; Id = 'settings'; PartitionKey = 'settings' }
    $days = if ($settings -and $settings['auditRetentionDays']) { [int]$settings['auditRetentionDays'] } else { 60 }
    $at = & $Context.Now
    $audit = [ordered]@{
        id            = 'aud-' + (New-DgUlid -Time $at)
        pk            = $PartitionKey
        type          = 'audit'
        schemaVersion = 1
        at            = Invoke-DgEngine -Name ConvertTo-DgTimestamp -Parameters @{ Value = $at }
        by            = $By
        action        = $Action
        changes       = @($Changes)
        ttl           = [Math]::Max(1, $days) * 86400
    }
    if ($DefinitionName) { $audit.definitionName = if ($DefinitionName.Length -gt 120) { $DefinitionName.Substring(0, 120) } else { $DefinitionName } }
    $audit
}
