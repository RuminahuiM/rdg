function Get-DgEngineVersion {
    <#
    .SYNOPSIS
        The RDG version, written into heartbeats and run records and returned by /api/health.
    .EXAMPLE
        Get-DgEngineVersion   # 0.1.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # The runbook build inlines the module as a dynamic module, which has no version of its own.
    $built = Get-Variable -Name DgEngineVersion -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($built) { return $built }
    # A release stamps ModuleVersion with MAJOR.MINOR.PATCH and PSData.Prerelease with the rest
    # (tools/Build-Release.ps1), so 1.2.0-rc.1 comes back whole.
    $module = $ExecutionContext.SessionState.Module
    $version = $module.Version.ToString(3)
    $prerelease = $null
    if ($module.PrivateData -is [hashtable] -and $module.PrivateData['PSData'] -is [hashtable]) {
        $prerelease = [string]$module.PrivateData['PSData']['Prerelease']
    }
    if ($prerelease) { "$version-$prerelease" } else { $version }
}
