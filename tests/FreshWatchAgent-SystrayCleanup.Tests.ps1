#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Systray Invoke-WatchTempCleanupMenu (I1 winget)' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        . (Join-Path $root 'scripts/lib/Launcher-Core.ps1')
        . (Join-Path $root 'tests/lib/FreshWindows-TestAstExtract.ps1')
        function global:Invoke-FreshAgentCleanup {
            param([switch]$Temp)
            return @{ ok = $true; message = 'stub' }
        }
        $watchPath = Join-Path $root 'scripts/GameMode-WatchAgent.ps1'
        $fnSrc = Get-FreshWindowsFunctionAstText -FilePath $watchPath -FunctionName 'Invoke-WatchTempCleanupMenu'
        function script:Show-Balloon {
            param($Title, $Text, $Icon)
            $script:LastBalloonTitle = $Title
            $script:LastBalloonText = $Text
            $script:LastBalloonIcon = $Icon
        }
        $script:FreshAppData = 'C:\TestUnused'
        . ([scriptblock]::Create($fnSrc))
    }

    AfterAll {
        Remove-Item -LiteralPath 'Function:\Global:Invoke-FreshAgentCleanup' -ErrorAction SilentlyContinue
    }

    It 'differe sans nettoyer si winget actif (controle immediat)' {
        $script:LastBalloonText = $null
        Mock Test-FreshWindowsWingetBusyForMaintenance { return $true }
        Mock Invoke-FreshAgentCleanup { throw 'systray cleanup must not run' }

        Invoke-WatchTempCleanupMenu

        $script:LastBalloonText | Should -Match 'Differe'
        Should -Invoke Invoke-FreshAgentCleanup -Times 0 -Exactly
    }

    It 'appelle Invoke-FreshAgentCleanup si winget inactif (mock)' {
        $script:LastBalloonText = $null
        Mock Test-FreshWindowsWingetBusyForMaintenance { return $false }
        Mock Invoke-FreshAgentCleanup { return @{ ok = $true; message = 'MOCK-SYSTRAY-OK' } }

        Invoke-WatchTempCleanupMenu

        $script:LastBalloonText | Should -Be 'MOCK-SYSTRAY-OK'
        Should -Invoke Invoke-FreshAgentCleanup -Times 1 -Exactly -ParameterFilter { $Temp }
    }
}
