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
        Test-FreshUninstallProcessImmune -ProcessId 99999 -CommandLine 'powershell -File C:\Temp\FreshWindows-Reinstall-x\Launch-AfterUninstall.ps1' | Should -Be $true
        Test-FreshUninstallProcessImmune -ProcessId 1 -CommandLine 'C:\Program Files\Refresh\Tool.exe' | Should -Be $false
    }

    It 'Test-FreshUninstallPathUnderRoot exige une frontiere de repertoire' {
        $base = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'FreshUninstallRootA')
        $nested = [System.IO.Path]::Combine($base, 'child')
        $sibling = $base + 'Extra'
        $outside = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'FreshUninstallRootB')
        Test-FreshUninstallPathUnderRoot -Path $nested -Root $base | Should -Be $true
        Test-FreshUninstallPathUnderRoot -Path $base -Root $base | Should -Be $true
        Test-FreshUninstallPathUnderRoot -Path $sibling -Root $base | Should -Be $false
        Test-FreshUninstallPathUnderRoot -Path $outside -Root $base | Should -Be $false
    }

    It 'Test-FreshUninstallCommandTargetsFreshRoot exige le separateur apres la racine' {
        $root = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) 'FreshWindows'))
        $scriptFile = [System.IO.Path]::Combine($root, 'Launch-GameModeWatch.ps1')
        $cmdOk = 'powershell -File "' + $scriptFile + '"'
        Test-FreshUninstallCommandTargetsFreshRoot -CommandLine $cmdOk -FreshRoot $root | Should -Be $true
        $evilRoot = $root + 'Backup'
        $cmdBad = 'powershell -File "' + [System.IO.Path]::Combine($evilRoot, 'tool.ps1') + '"'
        Test-FreshUninstallCommandTargetsFreshRoot -CommandLine $cmdBad -FreshRoot $root | Should -Be $false
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

    It 'DryRun ne supprime pas un dossier FreshWindows simule' {
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("fw-dryrun-{0}" -f [guid]::NewGuid().ToString('N'))
        $local = Join-Path $stage 'Local'
        $fresh = Join-Path $local 'FreshWindows'
        New-Item -ItemType Directory -Path $fresh -Force | Out-Null
        $savedLocal = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $local
        $DryRun = $true
        $Confirmed = $false
        $ReinstallAfter = $false
        try {
            $code = Invoke-FreshWindowsUninstall
            $code | Should -Be 0
            Test-Path -LiteralPath $fresh | Should -Be $true
        }
        finally {
            $env:LOCALAPPDATA = $savedLocal
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Uninstall stub relance' {
    It 'New-FreshUninstallReinstallStub parse sans erreur et pointe main' {
        if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
            $env:TEMP = [System.IO.Path]::GetTempPath()
        }
        $main = 'https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1'
        $stub = New-FreshUninstallReinstallStub -MainUrl $main
        Test-Path -LiteralPath $stub | Should -Be $true
        $raw = Get-Content -LiteralPath $stub -Raw -Encoding UTF8
        $raw | Should -Match 'raw\.githubusercontent\.com/nico2511/fresh_windows/main/launcher\.ps1'
        $raw | Should -Match 'FRESH_WIN_REF = ''main'''
        $raw | Should -Not -Match '\\"'
        $errs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($stub, [ref]$null, [ref]$errs)
        if ($errs) { ($errs | ForEach-Object { $_.Message }) -join '; ' | Should -Be '' }
        $stub | Should -Match 'FreshWindows-Reinstall'
        $stage = Split-Path -Parent $stub
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'launcher menu desinstallation' {
    It 'menu 12, epoch 57 et fonction Open-FreshWindowsUninstallMenu' {
        $lines = Get-Content -LiteralPath $script:LauncherPath -Encoding UTF8
        ($lines -join "`n") | Should -Match '12  Desinstallation'
        ($lines -join "`n") | Should -Match 'Open-FreshWindowsUninstallMenu'
        ($lines -join "`n") | Should -Match 'FreshWindowsLibEpoch = 57'
    }
}

Describe 'Confirm-FreshWindowsUninstallAction' {
    It 'annule sur non et ok/ouais' {
        Mock Read-Host { return 'non' }
        Confirm-FreshWindowsUninstallAction -Summary 'test' | Should -Be $false
        Mock Read-Host { return 'ok' }
        Confirm-FreshWindowsUninstallAction -Summary 'test' | Should -Be $false
        Mock Read-Host { return 'ouais' }
        Confirm-FreshWindowsUninstallAction -Summary 'test' | Should -Be $false
    }

    It 'accepte uniquement OUI exact' {
        Mock Read-Host { return 'OUI' }
        Confirm-FreshWindowsUninstallAction -Summary 'test' | Should -Be $true
        Mock Read-Host { return 'oui' }
        Confirm-FreshWindowsUninstallAction -Summary 'test' | Should -Be $false
    }
}

Describe 'suivi echecs et verification' {
    It 'Add-FreshUninstallStepFailure accumule les labels' {
        $script:FreshUninstallStepFailures = [System.Collections.ArrayList]@()
        Add-FreshUninstallStepFailure -Label 'suppression dossier'
        $script:FreshUninstallStepFailures.Count | Should -Be 1
    }

    It 'Get-FreshUninstallVerification signale raccourcis et fw-test restants' {
        $script:FreshUninstallVerificationErrors = [System.Collections.ArrayList]@()
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("fw-verify-{0}" -f [guid]::NewGuid().ToString('N'))
        $fw = Join-Path $stage 'fw-test-1'
        New-Item -ItemType Directory -Path $fw -Force | Out-Null
        $savedTemp = $env:TEMP
        $env:TEMP = $stage
        try {
            $v = Get-FreshUninstallVerification -FreshRoot (Join-Path $stage 'FreshWindows-missing')
            ($v.Issues -join ' ') | Should -Match 'fw-test'
        }
        finally {
            $env:TEMP = $savedTemp
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
