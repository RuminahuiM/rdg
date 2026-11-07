@{
    RootModule           = 'DgEngine.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '385ecf71-8fe1-47f6-b878-756fda3fc3bf'
    Author               = 'RDG contributors'
    Description          = 'RDG engine: rule language, evaluation and sync for rule-based Microsoft 365 groups.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Get-DgEngineVersion'
        'Get-DgPreview'
        'Invoke-DgSync'
        'Sync-DgSignInCertificate'
        'Test-DgRule'
        'Write-DgRunbookResult'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags = @('Entra', 'Groups', 'DynamicGroups', 'Exchange')
        }
    }
}
