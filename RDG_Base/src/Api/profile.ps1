# Runs once per worker (cold start). Modules/ holds DgApi, DgEngine and Microsoft.Graph.Authentication;
# the Functions host puts that folder on PSModulePath. No Az modules: tokens come from the identity endpoint.
$ErrorActionPreference = 'Stop'
Import-Module -Name DgApi
