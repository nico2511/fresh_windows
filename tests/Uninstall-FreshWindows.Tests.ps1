#Requires -Version 5.1
BeforeAll {
    $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
    $script:LibPath = Join-Path $root 'scripts/lib/FreshWindows-Uninstall.ps1'
    $script:LauncherCore = Join-Path $root 'scripts/lib/Launcher-Core.ps1'
    $script:LauncherPath = Join-Path $root 'launcher.ps1'
    . $script:LauncherCore
    . $script:LibPath -DryRun
}

Describe 'Get-FreshUninstallScheduledTaskSnapshot' {
    AfterEach { $script:FreshUninstallTaskSnapshotOverride = $null }

    It 'liste vide avec Ok=true ne doit pas etre $null (regression PS 5.1)' {
        $script:FreshUninstallTaskSnapshotOverride = {
            $list = [System.Collections.ArrayList]@()
            return [pscustomobject]@{ Ok = $true; Tasks = @($list.ToArray()); Error = '' }
        }
        $snap = Get-FreshUninstallScheduledTaskSnapshot
        $snap.Ok | Should -Be $true
        $null -eq $snap.Tasks | Should -Be $false
        @($snap.Tasks).Count | Should -Be 0
    }

    It 'echec API Ok=false distinct du succes vide' {
        $script:FreshUninstallTaskSnapshotOverride = {
            return [pscustomobject]@{ Ok = $false; Tasks = @(); Error = 'api down' }
        }
        $snap = Get-FreshUninstallScheduledTaskSnapshot
        $snap.Ok | Should -Be $false
        $snap.Error | Should -Match 'api down'
    }

    It 'verification n traite pas Ok=true liste vide comme indisponible' {
        $script:FreshUninstallTaskSnapshotOverride = {
            $list = [System.Collections.ArrayList]@()
            return [pscustomobject]@{ Ok = $true; Tasks = @($list.ToArray()); Error = '' }
        }
        $script:FreshUninstallVerificationErrors = [System.Collections.ArrayList]@()
        $v = Get-FreshUninstallVerification -FreshRoot (Join-Path ([System.IO.Path]::GetTempPath()) 'FreshWindows-verify')
        $v.Unavailable | Should -Be $false
    }
}

Describe 'Uninstall-FreshWindows helpers' {
    It 'Test-FreshUninstallProcessImmune utilise CommandLine' {
        Register-FreshUninstallImmuneProcessId -ProcessId 4242
        Test-FreshUninstallProcessImmune -ProcessId 4242 -CommandLine 'x' | Should -Be $true
        Test-FreshUninstallProcessImmune -ProcessId 9 -CommandLine 'Uninstall-FreshWindows.ps1' | Should -Be $true
    }

    It 'script tiers homonyme refuse si -File hors FreshRoot' {
        $fresh = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'FreshWindows')
        $otherScript = 'C:\Other\Launch-GameModeKill.ps1'
        $cmd = "powershell -File `"$otherScript`" -Arg `"$fresh\data`""
        Test-FreshUninstallCommandTargetsFreshRoot -CommandLine $cmd -FreshRoot $fresh | Should -Be $false
    }

    It 'Test-FreshUninstallPathUnderRoot frontiere repertoire' {
        $base = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'FreshUninstallRootA')
        $nested = [System.IO.Path]::Combine($base, 'child')
        $sibling = $base + 'Extra'
        Test-FreshUninstallPathUnderRoot -Path $nested -Root $base | Should -Be $true
        Test-FreshUninstallPathUnderRoot -Path $sibling -Root $base | Should -Be $false
    }

    It 'fw-test sans marqueur exclu de Owned' {
        if ([string]::IsNullOrWhiteSpace($env:TEMP)) { $env:TEMP = [System.IO.Path]::GetTempPath() }
        $d = Join-Path $env:TEMP 'fw-test-foreign'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        try {
            $inv = Get-FreshUninstallTempTestDirInventory
            ($inv.Unowned -contains $d) | Should -Be $true
            ($inv.Owned -contains $d) | Should -Be $false
        }
        finally {
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'DryRun ne supprime pas dossier FreshWindows simule' {
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("fw-dryrun-{0}" -f [guid]::NewGuid().ToString('N'))
        $local = Join-Path $stage 'Local'
        $fresh = Join-Path $local 'FreshWindows'
        New-Item -ItemType Directory -Path $fresh -Force | Out-Null
        try {
            . $script:LibPath -DryRun -SandboxLocalAppDataRoot $local
            $code = Invoke-FreshWindowsUninstall
            $code | Should -Be 0
            Test-Path -LiteralPath $fresh | Should -Be $true
        }
        finally {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'echecs enregistres empechent code succes implicite' {
        $script:FreshUninstallStepFailures = [System.Collections.ArrayList]@()
        Add-FreshUninstallStepFailure -Label 'etape test'
        $script:FreshUninstallStepFailures.Count | Should -BeGreaterThan 0
    }
}

Describe 'Uninstall stub relance' {
    It 'stub genere parse et refuse relance si Fresh reapparu' {
        if ([string]::IsNullOrWhiteSpace($env:TEMP)) { $env:TEMP = [System.IO.Path]::GetTempPath() }
        $main = 'https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1'
        $stub = New-FreshUninstallReinstallStub -MainUrl $main
        $errs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($stub, [ref]$null, [ref]$errs)
        if ($errs) { ($errs | ForEach-Object { $_.Message }) -join '; ' | Should -Be '' }
        $raw = Get-Content -LiteralPath $stub -Raw -Encoding UTF8
        $raw | Should -Match 'dossier Fresh toujours present'
        $stage = Split-Path -Parent $stub
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'launcher menu desinstallation' {
    It 'menu 12 epoch 58' {
        $lines = Get-Content -LiteralPath $script:LauncherPath -Encoding UTF8 -Raw
        $lines | Should -Match '12  Desinstallation'
        $lines | Should -Match 'FreshWindowsLibEpoch = 58'
    }
}

Describe 'Confirm-FreshWindowsUninstallAction' {
    It 'refuse oui espaces et ok' {
        Mock Read-Host { return 'oui' }
        Confirm-FreshWindowsUninstallAction -Summary 't' | Should -Be $false
        Mock Read-Host { return ' OUI' }
        Confirm-FreshWindowsUninstallAction -Summary 't' | Should -Be $false
        Mock Read-Host { return 'ok' }
        Confirm-FreshWindowsUninstallAction -Summary 't' | Should -Be $false
    }

    It 'accepte OUI exact seulement' {
        Mock Read-Host { return 'OUI' }
        Confirm-FreshWindowsUninstallAction -Summary 't' | Should -Be $true
    }
}
