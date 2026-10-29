function ConvertTo-DgRuleToken {
    <#
    .SYNOPSIS
        Splits rule text into tokens, each with its position.
    .DESCRIPTION
        Token kinds: LParen, RParen, LBracket, RBracket, Comma, String, Word, End.
        Words are everything else between whitespace and punctuation: properties, operators,
        unquoted values. The parser decides what a word means from where it stands.

        Strings use double or single quotes. Inside double quotes a backtick escapes a double
        quote (`"); inside single quotes a quote is doubled (''). A value written as `"Sales`"
        (backtick-quoted, no outer quotes) is the string "Sales" including the quotes. All as in
        Entra's documentation.

        En dash, em dash and minus sign at the start of a word count as a hyphen, because rules
        copied from Microsoft's documentation sometimes contain them (an en dash before ne).
    .EXAMPLE
        ConvertTo-DgRuleToken -State @{ Rule = 'user.department -eq "Sales"' }
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $rule = $State.Rule
    $length = $rule.Length
    $tokens = [System.Collections.Generic.List[object]]::new()
    $punctuation = @{ '(' = 'LParen'; ')' = 'RParen'; '[' = 'LBracket'; ']' = 'RBracket'; ',' = 'Comma' }
    $dashes = @([char]0x2013, [char]0x2014, [char]0x2212)
    $typographicQuotes = @([char]0x201C, [char]0x201D, [char]0x2018, [char]0x2019)

    $i = 0
    while ($i -lt $length) {
        $c = $rule[$i]

        if ([char]::IsWhiteSpace($c)) {
            $i++
            continue
        }

        $key = [string]$c
        if ($punctuation.ContainsKey($key)) {
            $tokens.Add((New-DgRuleToken -Kind $punctuation[$key] -Text $key -Value $key -Position $i -Length 1))
            $i++
            continue
        }

        if ($typographicQuotes -contains $c) {
            Invoke-DgRuleError -State $State -Position $i -Message "typographic quote $c found; use straight quotes "" or '"
        }

        # Entra's documented form for a value that itself contains quotes: `"Sales`" (no outer
        # quotes). The value keeps the quotes: "Sales".
        if ($c -eq [char]'`' -and $i + 1 -lt $length -and $rule[$i + 1] -eq [char]'"') {
            $start = $i
            $end = $rule.IndexOf('`"', $i + 2, [System.StringComparison]::Ordinal)
            if ($end -lt 0) {
                Invoke-DgRuleError -State $State -Position $start -Length ($length - $start) -Message 'text starting with `" is never closed with `"'
            }
            $inner = $rule.Substring($i + 2, $end - $i - 2)
            $i = $end + 2
            $tokens.Add((New-DgRuleToken -Kind 'String' -Text $rule.Substring($start, $i - $start) -Value ('"' + $inner + '"') -Position $start -Length ($i - $start)))
            continue
        }

        if ($c -eq [char]'"' -or $c -eq [char]"'") {
            $quote = $c
            $start = $i
            $builder = [System.Text.StringBuilder]::new()
            $closed = $false
            $i++
            while ($i -lt $length) {
                $ch = $rule[$i]
                if ($quote -eq [char]'"' -and $ch -eq [char]'`' -and $i + 1 -lt $length -and $rule[$i + 1] -eq [char]'"') {
                    [void]$builder.Append('"')
                    $i += 2
                    continue
                }
                if ($ch -eq $quote) {
                    if ($quote -eq [char]"'" -and $i + 1 -lt $length -and $rule[$i + 1] -eq [char]"'") {
                        [void]$builder.Append("'")
                        $i += 2
                        continue
                    }
                    $closed = $true
                    $i++
                    break
                }
                [void]$builder.Append($ch)
                $i++
            }
            if (-not $closed) {
                Invoke-DgRuleError -State $State -Position $start -Length ($length - $start) -Message "text starting with $quote is never closed"
            }
            $tokens.Add((New-DgRuleToken -Kind 'String' -Text $rule.Substring($start, $i - $start) -Value $builder.ToString() -Position $start -Length ($i - $start)))
            continue
        }

        # Word: up to the next whitespace, punctuation or quote.
        $start = $i
        while ($i -lt $length) {
            $ch = $rule[$i]
            if ([char]::IsWhiteSpace($ch) -or $punctuation.ContainsKey([string]$ch) -or $ch -eq [char]'"' -or $ch -eq [char]"'" -or $typographicQuotes -contains $ch) {
                break
            }
            $i++
        }
        $text = $rule.Substring($start, $i - $start)
        $value = if ($dashes -contains $text[0]) { '-' + $text.Substring(1) } else { $text }
        $tokens.Add((New-DgRuleToken -Kind 'Word' -Text $text -Value $value -Position $start -Length ($i - $start)))
    }

    $tokens.Add((New-DgRuleToken -Kind 'End' -Text '' -Value '' -Position $length -Length 0))
    , $tokens.ToArray()
}
