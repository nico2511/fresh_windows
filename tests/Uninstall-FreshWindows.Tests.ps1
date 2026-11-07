#Requires -Version 5.1
BeforeAll {
    $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
    $script:UninstallPath = Join-Path $root 'scripts/Uninstall-FreshWindows.ps1'
    $script:LauncherCore = Join-Path $root 'scripts/lib/Launcher-Core.ps1'
    $script:LauncherPath = Join-Path $root 'launcher.ps1'
    . $script:LauncherCore
    . $script:UninstallPath -DryRun
}

Describe 'Uninstall-FreshWindows helpers' {
    It 'Test-FreshUninstallProcessImmune protege ce script et la relance' {
        Test-FreshUninstallProcessImmune -ProcessId 99999 -CommandLine 'powershell -File C:\Temp\Uninstall-FreshWindows.ps1' | Should -Be $true
        Test-FreshUninstallProcessImmune -ProcessId 99999 -CommandLine 'powershell -File C:\ProgramData\FreshWindows\Launch-AfterUninstall.ps1' | Should -Be $true
        Test-FreshUninstallProcessImmune -ProcessId 1 -CommandLine 'C:\Program Files\Refresh\Tool.exe' | Should -Be $false
    }

    It 'Test-FreshUninstallPathUnderRoot refuse un chemin hors racine' {
        $base = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'FreshWindowsPathTest')
        $nested = [System.IO.Path]::Combine($base, 'child')
        $outside = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'FreshWindowsOutside')
        Test-FreshUninstallPathUnderRoot -Path $nested -Root $base | Should -Be $true
        Test-FreshUninstallPathUnderRoot -Path $outside -Root $base | Should -Be $false
    }

    It 'Invoke-FreshUninstallDoStep -DryRun n''execute pas le bloc' {
        $ran = $false
        $null = Invoke-FreshUninstallDoStep -Label 'test dry' -Action { $script:ran = $true }
        $ran | Should -Be $false
    }

    It 'refuse suppression sans Confirmed ni DryRun' {
        $DryRun = $false
        $Confirmed = $false
        $ReinstallAfter = $false
        $code = Invoke-FreshWindowsUninstall
        $code | Should -Be 2
    }
}

Describe 'Uninstall stub relance' {
    It 'Write-FreshUninstallReinstallStub pointe vers main launcher' {
        $script:DryRun = $false
        $stub = Write-FreshUninstallReinstallStub
        Test-Path -LiteralPath $stub | Should -Be $true
        $raw = Get-Content -LiteralPath $stub -Raw -Encoding UTF8
        $raw | Should -Match 'raw\.githubusercontent\.com/nico2511/fresh_windows/main/launcher\.ps1'
        $raw | Should -Match 'FRESH_WIN_REF = ''main'''
        $prog = if ($env:ProgramData) { $env:ProgramData } else { [System.IO.Path]::GetTempPath() }
        $stub | Should -Match ([regex]::Escape($prog.TrimEnd('/\')))
        Remove-Item -LiteralPath $stub -Force -ErrorAction SilentlyContinue
    }
}

Describe 'launcher menu desinstallation' {
    It 'menu 12 et fonction Open-FreshWindowsUninstallMenu' {
        $lines = Get-Content -LiteralPath $script:LauncherPath -Encoding UTF8
        ($lines -join "`n") | Should -Match '12  Desinstallation'
        ($lines -join "`n") | Should -Match 'Open-FreshWindowsUninstallMenu'
    }
}

Describe 'Confirm-FreshWindowsUninstallAction' {
    It 'annule sur entree autre que oui' {
        Mock Read-Host { return 'non' }
        Confirm-FreshWindowsUninstallAction -Summary 'test' | Should -Be $false
    }

    It 'accepte OUI en majuscules' {
        Mock Read-Host { return 'OUI' }
        Confirm-FreshWindowsUninstallAction -Summary 'test' | Should -Be $true
    }
}
