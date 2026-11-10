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
        $script:OrigLocalAppData = $env:LOCALAPPDATA
        $script:GuidRoot = Join-Path $tempRoot ('fw-maint-menu-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:GuidRoot -Force | Out-Null
        $script:FreshRoot = Join-Path $script:GuidRoot 'FreshWindows'
        New-Item -ItemType Directory -Path (Join-Path $script:FreshRoot 'lib') -Force | Out-Null
        $env:LOCALAPPDATA = $script:GuidRoot

        foreach ($pair in @{
                'FreshAgent-MaintenanceConfig.ps1' = (Get-Content -LiteralPath (Join-Path $root 'scripts/lib/FreshAgent-MaintenanceConfig.ps1') -Raw)
                'FreshAgent-Optimize.ps1'           = (Get-Content -LiteralPath (Join-Path $root 'scripts/lib/FreshAgent-Optimize.ps1') -Raw)
                'FreshAgent-Health.ps1'             = (Get-Content -LiteralPath (Join-Path $root 'scripts/lib/FreshAgent-Health.ps1') -Raw)
            }.GetEnumerator()) {
            Set-Content -LiteralPath (Join-Path $script:FreshRoot "lib\$($pair.Key)") -Value $pair.Value -Encoding UTF8
        }
    }

    AfterAll {
        $env:LOCALAPPDATA = $script:OrigLocalAppData
        if ($script:GuidRoot -and (Test-Path -LiteralPath $script:GuidRoot)) {
            Remove-Item -LiteralPath $script:GuidRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        foreach ($name in @(
                'Invoke-FreshAgentCleanup',
                'New-FreshAgentWeeklyHealthReport',
                'Get-FreshAgentAppDataRoot',
                'Get-FreshAgentMaintenanceConfig'
            )) {
            Remove-Item -LiteralPath "Function:\Global:$name" -ErrorAction SilentlyContinue
        }
    }

    It 'Import-FreshMaintenanceModules expose Invoke-FreshAgentCleanup dans la portee du script' {
        $ok = Import-FreshMaintenanceModules -FreshAppData $script:FreshRoot
        $ok | Should -Be $true
        Get-Command Invoke-FreshAgentCleanup -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command New-FreshAgentWeeklyHealthReport -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It 'Invoke-FreshMaintenanceTempCleanup retourne un message (pas absent)' {
        $r = Invoke-FreshMaintenanceTempCleanup -FreshAppData $script:FreshRoot -NoPause
        $r | Should -Not -BeNullOrEmpty
        $r.message | Should -Not -BeNullOrEmpty
        $r.message | Should -Not -Match 'Modules maintenance absents'
    }
}
