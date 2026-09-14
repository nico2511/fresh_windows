#Requires -Version 5.1
BeforeAll {
    $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
    . (Join-Path $root 'scripts/lib/Launcher-Core.ps1')
}

Describe 'Launcher-WinUtil' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        . (Join-Path $root 'scripts/lib/Launcher-WinUtil.ps1')
        $script:FreshAppData = Join-Path $env:TEMP 'FreshWindows-Test'
    }

    It 'Get-FreshWindowsLogDir crée le dossier logs sous FreshAppData' {
        $dir = Get-FreshWindowsLogDir
        $dir | Should -Match ([regex]::Escape('FreshWindows-Test'))
        $dir | Should -Match 'logs$'
        Test-Path -LiteralPath $dir | Should -Be $true
    }
}

Describe 'Launcher-Core' {
    It 'Get-WingetUpgradePowerShellCommand inclut source update et upgrade' {
        $cmd = Get-WingetUpgradePowerShellCommand
        $cmd | Should -Match 'winget source update'
        $cmd | Should -Match 'winget upgrade --all'
    }

    It 'Get-FreshWindowsLaunchStubContent fixe FRESH_WIN_REF et launcher irm' {
        $stub = Get-FreshWindowsLaunchStubContent -Ref 'abc123' -LauncherUrl 'https://example.com/launcher.ps1'
        $stub | Should -Match "FRESH_WIN_REF = 'abc123'"
        $stub | Should -Match 'https://example.com/launcher.ps1'
        $stub | Should -Match 'SilentMode'
    }
}
