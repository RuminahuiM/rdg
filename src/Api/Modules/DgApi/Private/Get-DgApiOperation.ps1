function Get-DgApiOperation {
    <#
    .SYNOPSIS
        Looks up an operation of the contract by operationId and returns its method, path and
        allowed roles (x-rdg-roles), so role checks follow openapi.yaml.
    .EXAMPLE
        Get-DgApiOperation -OperationId createDefinition   # Roles: admin
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $OperationId
    )

    $api = Get-DgOpenApi
    foreach ($path in $api.paths.Keys) {
        foreach ($method in $api.paths[$path].Keys) {
            $operation = $api.paths[$path][$method]
            if ($operation -isnot [System.Collections.IDictionary] -or $operation['operationId'] -ne $OperationId) { continue }
            return [pscustomobject]@{
                OperationId = $OperationId
                Method      = $method.ToUpperInvariant()
                Path        = $path
                Roles       = [string[]]@($operation['x-rdg-roles'])
            }
        }
    }
    throw "operation $OperationId is not in the API contract"
}
