@{
    RootModule           = 'DgApi.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'b1d0e9a4-6c3f-4f2a-9d7e-2c5b8a1f0e43'
    Author               = 'RDG contributors'
    Description          = 'RDG API helpers: request handling, roles, problems, audit, and one handler per OpenAPI operation.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Invoke-DgApiFunction'
        'Invoke-DgApiRequest'
        'Set-DgApiContext'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
