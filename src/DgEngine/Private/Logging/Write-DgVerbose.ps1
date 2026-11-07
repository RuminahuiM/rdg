function Write-DgVerbose {
    <#
    .SYNOPSIS
        Writes one line of the engine's own verbose log, when the setting "verbose logging" is on.
    .DESCRIPTION
        The engine never turns on $VerbosePreference: that would also log the verbose output of the
        modules it calls (module imports, every HTTP request with its full URL, Graph paging
        tokens that encode user principal names). Only lines written here reach the job's verbose
        stream. Invoke-DgSync switches it with Set-DgVerboseLogging. Keep the lines free of
        personal data: counts, definition names and results, no user names or addresses.
    .EXAMPLE
        Write-DgVerbose -Message "3 of 12 definitions due"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    if (Get-Variable -Name DgVerboseLogging -Scope Script -ValueOnly -ErrorAction SilentlyContinue) {
        Write-Verbose -Message $Message -Verbose
    }
}
