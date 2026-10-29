function Assert-DgIfMatch {
    <#
    .SYNOPSIS
        Checks the If-Match header against the stored document: missing ends with 428, outdated
        with 412 naming who changed it last. Returns the ETag to write with.
    .EXAMPLE
        $etag = Assert-DgIfMatch -Request $Request -Document $definition
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Request,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document
    )

    $sent = Get-DgRequestHeader -Request $Request -Name 'If-Match'
    if (-not $sent) { Stop-DgApi -Status 428 -Title 'If-Match header required' -Detail 'send the ETag from your last read' }
    $current = [string]$Document['_etag']
    if ($sent -ne $current -and $sent -ne '*') { Stop-DgPreconditionFailed -Document $Document }
    $current
}
