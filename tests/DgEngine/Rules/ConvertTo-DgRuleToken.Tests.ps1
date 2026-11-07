#Requires -Version 7.4

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../../src/DgEngine/DgEngine.psd1') -Force
}

Describe 'ConvertTo-DgRuleToken' {
    It 'splits a comparison into word, word, string, end with positions' {
        InModuleScope DgEngine {
            $tokens = ConvertTo-DgRuleToken -State @{ Rule = 'user.city -eq "Bern"' }
            ($tokens.Kind) -join '|' | Should -Be (@('Word', 'Word', 'String', 'End') -join '|')
            ($tokens.Position) -join '|' | Should -Be (@(0, 10, 14, 20) -join '|')
            $tokens[2].Value | Should -Be 'Bern'
            $tokens[2].Length | Should -Be 6
        }
    }

    It 'recognises punctuation' {
        InModuleScope DgEngine {
            $tokens = ConvertTo-DgRuleToken -State @{ Rule = '([a,b])' }
            ($tokens.Kind) -join '|' | Should -Be (@('LParen', 'LBracket', 'Word', 'Comma', 'Word', 'RBracket', 'RParen', 'End') -join '|')
        }
    }

    It 'unescapes `" inside double quotes and '''' inside single quotes' {
        InModuleScope DgEngine {
            (ConvertTo-DgRuleToken -State @{ Rule = '"a`"b"' })[0].Value | Should -Be 'a"b'
            (ConvertTo-DgRuleToken -State @{ Rule = "'O''Brien'" })[0].Value | Should -Be "O'Brien"
        }
    }

    It 'keeps a backtick that does not escape a quote' {
        InModuleScope DgEngine {
            (ConvertTo-DgRuleToken -State @{ Rule = '"a`b"' })[0].Value | Should -Be 'a`b'
        }
    }

    It 'turns a leading en dash into a hyphen but keeps the original text' {
        InModuleScope DgEngine {
            $token = (ConvertTo-DgRuleToken -State @{ Rule = "$([char]0x2013)ne" })[0]
            $token.Value | Should -Be '-ne'
            $token.Text | Should -Be "$([char]0x2013)ne"
        }
    }

    It 'treats tabs, line breaks and non-breaking spaces as whitespace' {
        InModuleScope DgEngine {
            $tokens = ConvertTo-DgRuleToken -State @{ Rule = "a`tb`r`nc$([char]0x00A0)d" }
            ($tokens.Value) -join '|' | Should -Be (@('a', 'b', 'c', 'd', '') -join '|')
        }
    }

    It 'reports an unclosed string at its opening quote' {
        InModuleScope DgEngine {
            { ConvertTo-DgRuleToken -State @{ Rule = 'x "abc' } } | Should -Throw -ExceptionType ([System.FormatException])
            try {
                ConvertTo-DgRuleToken -State @{ Rule = 'x "abc' }
            } catch {
                $_.Exception.Data['DgRuleError'].Position | Should -Be 2
            }
        }
    }
}

Describe 'Get-DgRuleOperatorName' {
    It 'returns the canonical name for <Word>' -ForEach @(
        @{ Word = '-eq'; Expected = 'eq' }
        @{ Word = 'EQ'; Expected = 'eq' }
        @{ Word = '-NotStartsWith'; Expected = 'notStartsWith' }
        @{ Word = 'any'; Expected = 'any' }
    ) {
        InModuleScope DgEngine -Parameters @{ Word = $Word; Expected = $Expected } {
            Get-DgRuleOperatorName -Word $Word | Should -BeExactly $Expected
        }
    }

    It 'returns nothing for a word that is not an operator' {
        InModuleScope DgEngine {
            Get-DgRuleOperatorName -Word 'user.city' | Should -BeNullOrEmpty
            Get-DgRuleOperatorName -Word '-gt' | Should -BeNullOrEmpty
        }
    }
}

Describe 'New-DgRuleError' {
    It 'computes 1-based line and column across line breaks' {
        InModuleScope DgEngine {
            $rule = "user.a -eq `"1`"`n-or user.b -eq"
            $ruleError = New-DgRuleError -Rule $rule -Position $rule.Length -Message 'x'
            $ruleError.Line | Should -Be 2
            $ruleError.Column | Should -Be 15
        }
    }
}
