#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Menu 11 maintenance modules (portee appelante)' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        . (Join-Path $root 'scripts/lib/Launcher-Core.ps1')

        $tempRoot = $env:TEMP
        if ([string]::IsNullOrWhiteSpace($tempRoot) -or $tempRoot -match '^:') {
            $tempRoot = if ($env:TMP -and $env:TMP -notmatch '^:') { $env:TMP } else { '/tmp' }
        }
        $script:SavedEnv = @{
            LOCALAPPDATA = $env:LOCALAPPDATA
            TEMP         = $env:TEMP
            TMP          = $env:TMP
            WINDIR       = $env:WINDIR
        }
        $script:GuidRoot = Join-Path $tempRoot ('fw-maint-menu-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:GuidRoot -Force | Out-Null
        $script:FreshRoot = Join-Path $script:GuidRoot 'FreshWindows'
        New-Item -ItemType Directory -Path (Join-Path $script:FreshRoot 'lib') -Force | Out-Null
        $env:LOCALAPPDATA = $script:GuidRoot
        $env:TEMP = Join-Path $script:GuidRoot 'UserTemp'
        $env:TMP = $env:TEMP
        New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
        Remove-Item -LiteralPath 'Env:\WINDIR' -ErrorAction SilentlyContinue

        foreach ($pair in @{
                'FreshAgent-MaintenanceConfig.ps1' = (Get-Content -LiteralPath (Join-Path $root 'scripts/lib/FreshAgent-MaintenanceConfig.ps1') -Raw)
                'FreshAgent-Optimize.ps1'           = (Get-Content -LiteralPath (Join-Path $root 'scripts/lib/FreshAgent-Optimize.ps1') -Raw)
                'FreshAgent-Health.ps1'             = (Get-Content -LiteralPath (Join-Path $root 'scripts/lib/FreshAgent-Health.ps1') -Raw)
            }.GetEnumerator()) {
            Set-Content -LiteralPath (Join-Path $script:FreshRoot "lib\$($pair.Key)") -Value $pair.Value -Encoding UTF8
        }
    }

    AfterAll {
        foreach ($name in @(
                'Invoke-FreshAgentCleanup',
                'New-FreshAgentWeeklyHealthReport',
                'Get-FreshAgentAppDataRoot',
                'Get-FreshAgentMaintenanceConfig'
            )) {
            Remove-Item -LiteralPath "Function:\Global:$name" -ErrorAction SilentlyContinue
        }
        if ($script:GuidRoot -and (Test-Path -LiteralPath $script:GuidRoot)) {
            Remove-Item -LiteralPath $script:GuidRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($script:SavedEnv) {
            foreach ($key in $script:SavedEnv.Keys) {
                if ($null -eq $script:SavedEnv[$key]) {
                    Remove-Item -LiteralPath "Env:\$key" -ErrorAction SilentlyContinue
                }
                else {
                    Set-Item -LiteralPath "Env:\$key" -Value $script:SavedEnv[$key]
                }
            }
        }
    }

    It 'Import-FreshMaintenanceModules expose Invoke-FreshAgentCleanup dans la portee du script' {
        $ok = Import-FreshMaintenanceModules -FreshAppData $script:FreshRoot
        $ok | Should -Be $true
        Get-Command Invoke-FreshAgentCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command New-FreshAgentWeeklyHealthReport -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Invoke-FreshMaintenanceTempCleanup differe si winget occupe (aucun nettoyage reel)' {
        $script:CleanupCalls = 0
        function global:Invoke-FreshAgentCleanup {
            param([switch]$Temp)
            if ($Temp) { $script:CleanupCalls++ }
            return @{ ok = $true; message = 'SHOULD-NOT-RUN' }
        }
        Mock Wait-FreshWindowsWingetIdleForMaintenance { return $false }

        $r = Invoke-FreshMaintenanceTempCleanup -FreshAppData $script:FreshRoot -NoPause
        $r.ok | Should -Be $false
        $r.message | Should -Match 'differe'
        $script:CleanupCalls | Should -Be 0
    }

    It 'Invoke-FreshMaintenanceTempCleanup appelle le nettoyage seulement si winget libre (simule)' {
        $script:CleanupCalls = 0
        function global:Invoke-FreshAgentCleanup {
            param([switch]$Temp)
            if ($Temp) {
                $script:CleanupCalls++
                return @{ ok = $true; message = 'MOCK-TEMP-OK' }
            }
            return @{ ok = $false; message = 'unexpected' }
        }
        Mock Wait-FreshWindowsWingetIdleForMaintenance { return $true }

        $r = Invoke-FreshMaintenanceTempCleanup -FreshAppData $script:FreshRoot -NoPause
        $r.ok | Should -Be $true
        $r.message | Should -Be 'MOCK-TEMP-OK'
        $script:CleanupCalls | Should -Be 1
    }
}
