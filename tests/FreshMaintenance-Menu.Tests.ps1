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

        $configBody = Get-Content -LiteralPath (Join-Path $root 'scripts/lib/FreshAgent-MaintenanceConfig.ps1') -Raw
        $healthBody = Get-Content -LiteralPath (Join-Path $root 'scripts/lib/FreshAgent-Health.ps1') -Raw
        Set-Content -LiteralPath (Join-Path $script:FreshRoot 'lib\FreshAgent-MaintenanceConfig.ps1') -Value $configBody -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:FreshRoot 'lib\FreshAgent-Health.ps1') -Value $healthBody -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:FreshRoot 'lib\FreshAgent-GameSession.ps1') -Value '# stub' -Encoding UTF8
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

    It 'Import-FreshMaintenanceModules expose Invoke-FreshAgentCleanup' {
        Set-Content -LiteralPath (Join-Path $script:FreshRoot 'lib\FreshAgent-Optimize.ps1') -Value @'
#Requires -Version 5.1
function Invoke-FreshAgentCleanup { param([switch]$Temp) return @{ ok = $true; message = 'MAINT-REV-0' } }
'@ -Encoding UTF8
        $ok = Import-FreshMaintenanceModules -FreshAppData $script:FreshRoot
        $ok | Should -Be $true
        Get-Command Invoke-FreshAgentCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Import-FreshMaintenanceModules rafraichit Global apres resync (v1 puis v2)' {
        Set-Content -LiteralPath (Join-Path $script:FreshRoot 'lib\FreshAgent-Optimize.ps1') -Value @'
#Requires -Version 5.1
function Invoke-FreshAgentCleanup { param([switch]$Temp) return @{ ok = $true; message = 'MAINT-REV-1' } }
'@ -Encoding UTF8
        Import-FreshMaintenanceModules -FreshAppData $script:FreshRoot | Should -Be $true
        (Invoke-FreshAgentCleanup -Temp).message | Should -Be 'MAINT-REV-1'

        Set-Content -LiteralPath (Join-Path $script:FreshRoot 'lib\FreshAgent-Optimize.ps1') -Value @'
#Requires -Version 5.1
function Invoke-FreshAgentCleanup { param([switch]$Temp) return @{ ok = $true; message = 'MAINT-REV-2' } }
'@ -Encoding UTF8
        Import-FreshMaintenanceModules -FreshAppData $script:FreshRoot | Should -Be $true
        (Invoke-FreshAgentCleanup -Temp).message | Should -Be 'MAINT-REV-2'
    }

    It 'Invoke-FreshMaintenanceTempCleanup differe si winget occupe (Mock, 0 nettoyage)' {
        Set-Content -LiteralPath (Join-Path $script:FreshRoot 'lib\FreshAgent-Optimize.ps1') -Value @'
#Requires -Version 5.1
function Invoke-FreshAgentCleanup { param([switch]$Temp) throw 'REAL-CLEANUP-FORBIDDEN' }
'@ -Encoding UTF8
        Import-FreshMaintenanceModules -FreshAppData $script:FreshRoot | Out-Null
        Mock Wait-FreshWindowsWingetIdleForMaintenance { return $false }
        Mock Invoke-FreshAgentCleanup { throw 'should not run' }

        $r = Invoke-FreshMaintenanceTempCleanup -FreshAppData $script:FreshRoot -NoPause
        $r.ok | Should -Be $false
        $r.message | Should -Match 'differe'
        Should -Invoke Invoke-FreshAgentCleanup -Times 0 -Exactly
    }

    It 'Invoke-FreshMaintenanceTempCleanup simule 1 nettoyage si winget libre' {
        Set-Content -LiteralPath (Join-Path $script:FreshRoot 'lib\FreshAgent-Optimize.ps1') -Value @'
#Requires -Version 5.1
function Invoke-FreshAgentCleanup { param([switch]$Temp) throw 'REAL-CLEANUP-FORBIDDEN' }
'@ -Encoding UTF8
        Import-FreshMaintenanceModules -FreshAppData $script:FreshRoot | Out-Null
        Mock Wait-FreshWindowsWingetIdleForMaintenance { return $true }
        Mock Invoke-FreshAgentCleanup { return @{ ok = $true; message = 'MOCK-TEMP-OK' } }

        $r = Invoke-FreshMaintenanceTempCleanup -FreshAppData $script:FreshRoot -NoPause
        $r.ok | Should -Be $true
        $r.message | Should -Be 'MOCK-TEMP-OK'
        Should -Invoke Invoke-FreshAgentCleanup -Times 1 -Exactly -ParameterFilter { $Temp }
    }
}
