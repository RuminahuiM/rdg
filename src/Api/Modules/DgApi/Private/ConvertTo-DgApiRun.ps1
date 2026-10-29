function ConvertTo-DgApiRun {
    <#
    .SYNOPSIS
        Maps a run record to the API's Run object, with a link to the Automation job.
    .EXAMPLE
        ConvertTo-DgApiRun -Document $run -AutomationAccountId $context.AutomationAccountId
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document,

        [string] $AutomationAccountId
    )

    $run = [ordered]@{
        id           = $Document['id']
        definitionId = if ($Document['pk'] -eq 'system') { $null } else { $Document['pk'] }
    }
    foreach ($key in $Document.Keys) {
        if ($key -in @('id', 'pk', 'type', 'schemaVersion', 'ttl') -or $key -like '_*') { continue }
        # Plain assignment: an if-expression would turn lists with one or no entries into a value or $null.
        $run[$key] = $Document[$key]
        if ($key -eq 'startedAt') { $run[$key] = ConvertTo-DgApiTime -Value $Document[$key] }
    }
    if ($AutomationAccountId -and $Document['jobId']) {
        $run['jobUrl'] = "https://portal.azure.com/#resource$($AutomationAccountId.TrimEnd('/'))/jobs/$($Document['jobId'])"
    }
    $run
}
