#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'GameMode-WatchAgent mutex (code reel, noms GUID)' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        . (Join-Path $root 'tests/lib/FreshWindows-TestAstExtract.ps1')
        $script:WatchPath = Join-Path $root 'scripts/GameMode-WatchAgent.ps1'

        function script:Write-WatchLog { param($Message) }
        function script:Get-FreshWatchAgentPeerProcesses { return @() }

        $legacySrc = Get-FreshWindowsFunctionAstText -FilePath $script:WatchPath -FunctionName 'Test-FreshWatchLegacyMaintenanceMutexHeld'
        $namesSrc = Get-FreshWindowsFunctionAstText -FilePath $script:WatchPath -FunctionName 'Get-FreshWatchLegacyMaintenanceMutexNames'
        $enterSrc = Get-FreshWindowsFunctionAstText -FilePath $script:WatchPath -FunctionName 'Enter-FreshWatchAgentSingleInstance'

        . ([scriptblock]::Create($namesSrc))
        . ([scriptblock]::Create($legacySrc))
        . ([scriptblock]::Create($enterSrc))
    }

    It 'Enter-FreshWatchAgentSingleInstance -WhatIf quitte si mutex principal GUID deja tenu (processus enfant)' {
        $suffix = [guid]::NewGuid().ToString('N')
        $primary = "Global\FreshWindowsWatchAgent-Test-$suffix"
        $sandbox = Join-Path ((if ($env:TEMP -and $env:TEMP -notmatch '^:') { $env:TEMP } else { '/tmp' })) "fw-enter-mutex-$suffix"
        New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
        $stopFile = Join-Path $sandbox 'stop.flag'
        $logFile = Join-Path $sandbox 'child.log'
        $holder = @"
`$ErrorActionPreference = 'Stop'
`$m = New-Object System.Threading.Mutex(`$false, '$primary')
[void]`$m.WaitOne()
Set-Content -LiteralPath '$logFile' -Value 'holding' -Encoding UTF8
while (-not (Test-Path -LiteralPath '$stopFile')) { Start-Sleep -Milliseconds 100 }
try { [void]`$m.ReleaseMutex() } catch { }
try { `$m.Dispose() } catch { }
"@
        $proc = $null
        try {
            $proc = Start-Process -FilePath (Get-Process -Id $PID).Path `
                -ArgumentList @('-NoProfile', '-Command', $holder) -WorkingDirectory $sandbox -PassThru
            $deadline = (Get-Date).AddSeconds(8)
            while ((Get-Date) -lt $deadline) {
                if (Test-Path -LiteralPath $logFile) { break }
                Start-Sleep -Milliseconds 100
            }
            Test-Path -LiteralPath $logFile | Should -Be $true
            $r = Enter-FreshWatchAgentSingleInstance -PrimaryMutexName $primary -LegacyMutexNames @("Global\Legacy-Test-$suffix") -WhatIf
            $r.shouldExit | Should -Be $true
            $r.reason | Should -Be 'primary-mutex-busy'
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

    It 'Enter-FreshWatchAgentSingleInstance -WhatIf acquiert un mutex GUID libre' {
        $suffix = [guid]::NewGuid().ToString('N')
        $primary = "Global\FreshWindowsWatchAgent-Test-$suffix"
        $r = Enter-FreshWatchAgentSingleInstance -PrimaryMutexName $primary -LegacyMutexNames @("Global\Legacy-Test-$suffix") -WhatIf
        $r.shouldExit | Should -Be $false
        $r.acquired | Should -Be $true
        if ($script:WatchMutex) {
            try { [void]$script:WatchMutex.ReleaseMutex() } catch { }
            try { $script:WatchMutex.Dispose() } catch { }
            $script:WatchMutex = $null
        }
    }

    It 'Test-FreshWatchLegacyMaintenanceMutexHeld ne voit que les noms GUID fournis' {
        $suffix = [guid]::NewGuid().ToString('N')
        $legacyName = "Global\FreshAgentWatchAgent-Test-$suffix"
        $names = @($legacyName)
        Test-FreshWatchLegacyMaintenanceMutexHeld -LegacyMutexNames $names | Should -Be $false
        $sandbox = Join-Path ((if ($env:TEMP -and $env:TEMP -notmatch '^:') { $env:TEMP } else { '/tmp' })) "fw-legacy-only-$suffix"
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
            $proc = Start-Process -FilePath (Get-Process -Id $PID).Path `
                -ArgumentList @('-NoProfile', '-Command', $holder) -WorkingDirectory $sandbox -PassThru
            Start-Sleep -Seconds 1
            Test-FreshWatchLegacyMaintenanceMutexHeld -LegacyMutexNames $names | Should -Be $true
            $r = Enter-FreshWatchAgentSingleInstance -PrimaryMutexName "Global\FreshWindowsWatchAgent-Test-$suffix" -LegacyMutexNames $names -WhatIf
            $r.shouldExit | Should -Be $true
            $r.reason | Should -Be 'legacy-mutex'
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
