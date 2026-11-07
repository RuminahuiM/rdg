# Lint rules for all PowerShell in this repo. Used by tools/Invoke-Lint.ps1 and CI.
@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @()

    Rules        = @{
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('7.0')  # syntax profile for PowerShell 7.x; runtime is 7.4
        }
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }
        PSUseConsistentWhitespace  = @{
            Enable                                  = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckSeparator                          = $true
            CheckInnerBrace                         = $true
            CheckPipe                               = $true
            # Hashtables are aligned (VS Code formatter default); see PSAlignAssignmentStatement.
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSAvoidUsingCmdletAliases  = @{
            Enable = $true
        }
    }
}
