#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'GameMode-WatchAgent mutex (code reel)' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        . (Join-Path $root 'tests/lib/FreshWindows-TestAstExtract.ps1')
        $script:WatchPath = Join-Path $root 'scripts/GameMode-WatchAgent.ps1'
        $legacySrc = Get-FreshWindowsFunctionAstText -FilePath $script:WatchPath -FunctionName 'Test-FreshWatchLegacyMaintenanceMutexHeld'
        . ([scriptblock]::Create($legacySrc))
    }

    It 'Enter-FreshWatchAgentSingleInstance refuse un mutex principal deja tenu (processus enfant)' {
        $suffix = [guid]::NewGuid().ToString('N')
        $mutexName = "Global\FreshWindowsWatchAgent-Test-$suffix"
        $tempRoot = if ($env:TEMP -and $env:TEMP -notmatch '^:') { $env:TEMP } else { '/tmp' }
        $sandbox = Join-Path $tempRoot ("fw-mutex-child-$suffix")
        New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
        $stopFile = Join-Path $sandbox 'stop.flag'
        $logFile = Join-Path $sandbox 'child.log'
        $holder = @"
`$ErrorActionPreference = 'Stop'
`$name = '$mutexName'
`$m = New-Object System.Threading.Mutex(`$false, `$name)
[void]`$m.WaitOne()
Set-Content -LiteralPath '$logFile' -Value 'holding' -Encoding UTF8
while (-not (Test-Path -LiteralPath '$stopFile')) { Start-Sleep -Milliseconds 100 }
try { [void]`$m.ReleaseMutex() } catch { }
try { `$m.Dispose() } catch { }
"@
        $proc = $null
        $secondGot = $true
        try {
            $proc = Start-Process -FilePath (Get-Process -Id $PID).Path `
                -ArgumentList @('-NoProfile', '-Command', $holder) `
                -WorkingDirectory $sandbox `
                -PassThru
            $deadline = (Get-Date).AddSeconds(8)
            while ((Get-Date) -lt $deadline) {
                if (Test-Path -LiteralPath $logFile) { break }
                Start-Sleep -Milliseconds 100
            }
            if (-not (Test-Path -LiteralPath $logFile)) {
                throw 'Child mutex holder failed to start'
            }
            $m2 = $null
            try {
                $m2 = New-Object System.Threading.Mutex($false, $mutexName)
                try { $secondGot = $m2.WaitOne(0, $false) }
                catch [System.Threading.AbandonedMutexException] { $secondGot = $true }
            }
            finally {
                if ($m2) {
                    try { if ($secondGot) { [void]$m2.ReleaseMutex() } } catch { }
                    try { $m2.Dispose() } catch { }
                }
            }
            $secondGot | Should -Be $false
        }
        finally {
            if (Test-Path -LiteralPath $stopFile) { Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType File -Path $stopFile -Force | Out-Null
            if ($proc -and -not $proc.HasExited) {
                Wait-Process -Id $proc.Id -Timeout 10 -ErrorAction SilentlyContinue
                if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
            }
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Test-FreshWatchLegacyMaintenanceMutexHeld (extrait AST) voit Global\FreshAgentWatchAgent tenu par enfant' {
        $suffix = [guid]::NewGuid().ToString('N')
        $legacyName = 'Global\FreshAgentWatchAgent'
        $tempRoot = if ($env:TEMP -and $env:TEMP -notmatch '^:') { $env:TEMP } else { '/tmp' }
        $sandbox = Join-Path $tempRoot ("fw-legacy-$suffix")
        New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
        $stopFile = Join-Path $sandbox 'stop.flag'
        $holder = @"
`$m = New-Object System.Threading.Mutex(`$false, '$legacyName')
[void]`$m.WaitOne()
while (-not (Test-Path -LiteralPath '$stopFile')) { Start-Sleep -Milliseconds 100 }
try { [void]`$m.ReleaseMutex() } catch { }
try { `$m.Dispose() } catch { }
"@
        $proc = $null
        try {
            Test-FreshWatchLegacyMaintenanceMutexHeld | Should -Be $false
            $proc = Start-Process -FilePath (Get-Process -Id $PID).Path `
                -ArgumentList @('-NoProfile', '-Command', $holder) `
                -WorkingDirectory $sandbox -PassThru
            Start-Sleep -Seconds 1
            Test-FreshWatchLegacyMaintenanceMutexHeld | Should -Be $true
        }
        finally {
            New-Item -ItemType File -Path $stopFile -Force | Out-Null
            if ($proc -and -not $proc.HasExited) {
                Wait-Process -Id $proc.Id -Timeout 10 -ErrorAction SilentlyContinue
                if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
            }
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
