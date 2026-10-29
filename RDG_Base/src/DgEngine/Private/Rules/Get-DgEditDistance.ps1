function Get-DgEditDistance {
    <#
    .SYNOPSIS
        Levenshtein distance between two strings (insertions, deletions, substitutions).
    .EXAMPLE
        Get-DgEditDistance -First 'extensionatribute3' -Second 'extensionattribute3'   # 1
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $First,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Second
    )

    $previous = [int[]](0..$Second.Length)
    for ($i = 1; $i -le $First.Length; $i++) {
        $current = [int[]]::new($Second.Length + 1)
        $current[0] = $i
        for ($j = 1; $j -le $Second.Length; $j++) {
            $cost = if ($First[$i - 1] -ceq $Second[$j - 1]) { 0 } else { 1 }
            $current[$j] = [Math]::Min([Math]::Min($current[$j - 1] + 1, $previous[$j] + 1), $previous[$j - 1] + $cost)
        }
        $previous = $current
    }
    $previous[$Second.Length]
}
