#Requires -Version 7.4
# Contract validation in the API: the inlined schema accepts and rejects the same bodies as the
# contract (tests/Fixtures/api, also checked by tools/check-contracts.mjs) and names the field.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'ApiTestKit.ps1')

    function Get-SchemaError {
        param([string] $Json, [string] $Schema)
        InModuleScope DgApi -Parameters @{ J = $Json; S = $Schema } {
            param($J, $S)
            Test-DgApiSchema -Json $J -Schema $S
        }
    }
}

Describe 'Test-DgApiSchema' {
    It 'judges the API fixture <Name> like the contract check does' -ForEach @(
        Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/api') -Filter '*.json' |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        # Raw JSON of the body: a round trip through ConvertFrom-Json would turn dates into DateTime.
        $document = [System.Text.Json.JsonDocument]::Parse((Get-Content -Raw -Path $Path))
        $root = $document.RootElement
        $errors = @(Get-SchemaError -Json $root.GetProperty('body').GetRawText() -Schema $root.GetProperty('schema').GetString())
        if ($root.GetProperty('valid').GetBoolean()) {
            $errors | Should -HaveCount 0
        } else {
            $errors.Count | Should -BeGreaterThan 0
        }
    }

    It 'names a field nested behind a reference' {
        $body = '{"name":"Sales","groupType":"Security","target":{"mode":"elsewhere","groupId":"0b7d2c1e-5a4f-4e3b-9c8d-7f6e5d4c3b2a"},"rule":"user.department -eq \"Sales\""}'
        $errors = @(Get-SchemaError -Json $body -Schema 'DefinitionInput')
        $errors[0].field | Should -Be 'target.mode'
    }
}

Describe 'Resolve-DgApiSchemaRef' {
    It 'replaces a reference and merges a single allOf entry' {
        $result = InModuleScope DgApi {
            $definitions = @{
                Name  = @{ type = 'string'; minLength = 1 }
                Base  = @{ type = 'object'; required = @('a'); properties = @{ a = @{ '$ref' = '#/$defs/Name' } } }
                Input = @{ allOf = @(@{ '$ref' = '#/$defs/Base' }); required = @('b'); properties = @{ b = @{ type = 'integer' } }; unevaluatedProperties = $false }
            }
            Resolve-DgApiSchemaRef -Node $definitions['Input'] -Definitions $definitions
        }
        $result.Contains('allOf') | Should -BeFalse
        $result['properties']['a']['minLength'] | Should -Be 1
        $result['properties']['b']['type'] | Should -Be 'integer'
        @($result['required']) | Sort-Object | Should -Be @('a', 'b')
        $result['unevaluatedProperties'] | Should -BeFalse
    }

    It 'keeps allOf when merging would change what is valid' {
        $result = InModuleScope DgApi {
            # additionalProperties in the entry only sees the entry's own properties.
            $definitions = @{
                Closed = @{ type = 'object'; properties = @{ a = @{ type = 'string' } }; additionalProperties = $false }
                Input  = @{ allOf = @(@{ '$ref' = '#/$defs/Closed' }); properties = @{ b = @{ type = 'string' } } }
            }
            Resolve-DgApiSchemaRef -Node $definitions['Input'] -Definitions $definitions
        }
        $result.Contains('allOf') | Should -BeTrue
        $result['properties'].Contains('a') | Should -BeFalse
    }

    It 'keeps a reference whose target constrains the same keyword' {
        $result = InModuleScope DgApi {
            $definitions = @{ Short = @{ type = 'string'; maxLength = 5 } }
            Resolve-DgApiSchemaRef -Node @{ '$ref' = '#/$defs/Short'; maxLength = 10 } -Definitions $definitions
        }
        $result['$ref'] | Should -Be '#/$defs/Short'
        $result['maxLength'] | Should -Be 10
    }
}
