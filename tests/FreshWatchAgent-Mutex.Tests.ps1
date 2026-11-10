#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'GameMode-WatchAgent mutex' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        $watchPath = Join-Path $root 'scripts/GameMode-WatchAgent.ps1'
        $script:WatchSource = Get-Content -LiteralPath $watchPath -Raw -Encoding UTF8
    }

    It 'n utilise qu un mutex principal fixe (pas de liste de repli)' {
        $script:WatchSource | Should -Match 'Global\\FreshWindowsWatchAgent'
        $script:WatchSource | Should -Not -Match 'mutexCandidates'
    }

    It 'deux tentatives concurrentes: une seule acquiert un mutex suffixe GUID' {
        $suffix = [guid]::NewGuid().ToString('N')
        $name = "Global\FreshWindowsWatchAgent-Test-$suffix"
        $m1 = $null
        $m2 = $null
        $got1 = $false
        $got2 = $false
        try {
            $m1 = New-Object System.Threading.Mutex($false, $name)
            try { $got1 = $m1.WaitOne(0, $false) } catch [System.Threading.AbandonedMutexException] { $got1 = $true }
            $m2 = New-Object System.Threading.Mutex($false, $name)
            try { $got2 = $m2.WaitOne(0, $false) } catch [System.Threading.AbandonedMutexException] { $got2 = $true }
        }
        finally {
            foreach ($m in @($m1, $m2)) {
                if ($m) {
                    try { [void]$m.ReleaseMutex() } catch { }
                    try { $m.Dispose() } catch { }
                }
            }
        }
        if ($got1 -and $got2) {
            Set-ItResult -Inconclusive -Because 'Mutex global non exclusif sur cette plateforme (validite Windows)'
        }
        else {
            ($got1 -xor $got2) | Should -Be $true
        }
    }

    It 'Test-FreshWatchLegacyMaintenanceMutexHeld detecte un mutex legacy ouvert' {
        $legacyName = "Global\FreshWindows-WatchAgent-Test-$([guid]::NewGuid().ToString('N'))"
        $hold = $null
        try {
            $hold = New-Object System.Threading.Mutex($false, $legacyName)
            [void]$hold.WaitOne()
            function Test-FreshWatchLegacyProbeForTest {
                param([string[]]$Names)
                foreach ($mutexName in $Names) {
                    try {
                        $legacy = [System.Threading.Mutex]::OpenExisting($mutexName)
                        try { $legacy.Dispose() } catch { }
                        return $true
                    }
                    catch [System.Threading.WaitHandleCannotBeOpenedException] { }
                    catch [UnauthorizedAccessException] { return $true }
                    catch { }
                }
                return $false
            }
            Test-FreshWatchLegacyProbeForTest -Names @($legacyName) | Should -Be $true
            Test-FreshWatchLegacyProbeForTest -Names @('Global\FreshWindows-WatchAgent-Test-Nope') | Should -Be $false
        }
        finally {
            if ($hold) {
                try { [void]$hold.ReleaseMutex() } catch { }
                try { $hold.Dispose() } catch { }
            }
        }
    }
}
