function ConvertTo-DgApiAudit {
    <#
    .SYNOPSIS
        Maps an audit record to the API's AuditEntry object.
    .EXAMPLE
        ConvertTo-DgApiAudit -Document $audit
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document
    )

    $entry = [ordered]@{
        id           = $Document['id']
        definitionId = if ($Document['pk'] -eq 'settings') { $null } else { $Document['pk'] }
        at           = ConvertTo-DgApiTime -Value $Document['at']
        by           = $Document['by']
        action       = $Document['action']
        changes      = @($Document['changes'] | Where-Object { $null -ne $_ })
    }
    if ($Document['definitionName']) { $entry['definitionName'] = $Document['definitionName'] }
    $entry
}
