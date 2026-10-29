function Format-DgOutcomeLine {
    <#
    .SYNOPSIS
        One verbose line per synced definition: result, members, changes, duration.
    .DESCRIPTION
        Counts only, no user names: the verbose log must not carry personal data.
        A dry run also names what a real run would have done ("then").
    .EXAMPLE
        Format-DgOutcomeLine -Outcome $outcome
        # Finance: DryRun (readOnly), 24 members, +24/-3, 0 skipped, 812 ms; then Blocked: 27 changes ...
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Outcome
    )

    $get = { param($name) Get-DgFieldValue -Object $Outcome -Name $name }
    $result = [string](& $get 'Result')
    $reason = [string](& $get 'DryRunReason')
    $line = "$(& $get 'Name'): $result"
    if ($reason) { $line += " ($reason)" }
    $members = & $get 'MemberCount'
    if ($null -ne $members) { $line += ", $members members" }
    $line += ", +$([int](& $get 'Added'))/-$([int](& $get 'Removed')), $([int](& $get 'Skipped')) skipped, $([long](& $get 'DurationMs')) ms"
    $then = & $get 'Then'
    if ($then) {
        $thenResult = [string](Get-DgFieldValue -Object $then -Name 'result')
        $thenDetail = [string](Get-DgFieldValue -Object $then -Name 'message')
        $line += "; then $thenResult"
        if ($thenDetail) { $line += ": $thenDetail" }
    }
    $errorText = [string](& $get 'Error')
    if ($errorText) { $line += "; error: $errorText" }
    $line
}
