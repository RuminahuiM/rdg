#Requires -Version 7.4
# tools/Start-ApiLocal.ps1 serves the real routes over HTTP.

Describe 'Start-ApiLocal' {
    It 'serves health, me and a definition over HTTP' {
        $port = Get-Random -Minimum 20000 -Maximum 40000
        $script = Join-Path -Path $PSScriptRoot -ChildPath '../../tools/Start-ApiLocal.ps1'
        $pwsh = (Get-Process -Id $PID).Path
        $process = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $script, '-Port', $port, '-MaxRequests', '4', '-Role', 'reader') -PassThru -RedirectStandardOutput ([System.IO.Path]::GetTempFileName())
        try {
            $health = $null
            for ($i = 0; $i -lt 60 -and -not $health; $i++) {
                Start-Sleep -Milliseconds 500
                try { $health = Invoke-RestMethod -Uri "http://localhost:$port/api/health" } catch { $health = $null }
            }
            $health.status | Should -Be 'ok'
            (Invoke-RestMethod -Uri "http://localhost:$port/api/me").roles | Should -Be 'reader'
            $list = Invoke-RestMethod -Uri "http://localhost:$port/api/definitions"
            $list.items[0].name | Should -Be 'Sales'
            $definition = Invoke-WebRequest -Uri "http://localhost:$port/api/definitions/$($list.items[0].id)" -SkipHttpErrorCheck
            $definition.StatusCode | Should -Be 200
            $definition.Headers['ETag'] | Should -Not -BeNullOrEmpty
        } finally {
            if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        }
    }
}
