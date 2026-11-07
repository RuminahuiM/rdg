function Select-DgPage {
    <#
    .SYNOPSIS
        Returns one page of a list (up to 50 items) and the continuation token for the next one.
        The token is opaque to clients; a token that can't be read ends with 400.
    .EXAMPLE
        Select-DgPage -Items $all -Token (Get-DgRequestValue -Request $Request -Part Query -Name continuationToken)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Items,

        [AllowNull()]
        [string] $Token,

        [ValidateRange(1, 50)]
        [int] $PageSize = 50
    )

    $offset = 0
    if ($Token) {
        try {
            $text = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Token))
            if ($text -notmatch '^o:(\d{1,9})$') { throw 'format' }
            $offset = [int]$Matches[1]
        } catch {
            Stop-DgApi -Status 400 -Title 'Invalid continuation token' -Type 'validation'
        }
    }
    $page = [object[]]@($Items | Select-Object -Skip $offset -First $PageSize)
    $next = $offset + $page.Count
    [ordered]@{
        items             = $page
        continuationToken = if ($next -lt $Items.Count) { [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("o:$next")) } else { $null }
    }
}
