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
    AfterEach {
        $script:FreshUninstallTaskSnapshotOverride = $null
        $script:FreshUninstallProcessEnumeratorOverride = $null
    }

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
        $script:FreshUninstallProcessEnumeratorOverride = { return @() }
        $v = Get-FreshUninstallVerification -FreshRoot (Join-Path ([System.IO.Path]::GetTempPath()) 'FreshWindows-verify')
        $v.Unavailable | Should -Be $false
    }
}

Describe 'Enumeration processus (I1)' {
    BeforeEach {
        $script:FreshUninstallVerificationErrors = [System.Collections.ArrayList]@()
    }

    It 'absence normale (NoProcessFoundForGivenName) ne marque pas indisponible' {
        Mock Get-Process {
            $ex = New-Object System.Management.Automation.ItemNotFoundException 'pwsh'
            $err = [System.Management.Automation.ErrorRecord]::new(
                $ex,
                'NoProcessFoundForGivenName,Microsoft.PowerShell.Commands.GetProcessCommand',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                'pwsh'
            )
            $PSCmdlet.WriteError($err)
        } -ParameterFilter { $Name -eq 'pwsh' -and $ErrorAction -eq 'SilentlyContinue' }
        Mock Get-Process { return @() } -ParameterFilter { $Name -ne 'pwsh' }

        $null = Get-FreshUninstallProcessListByName -Name 'pwsh'
        $script:FreshUninstallVerificationErrors.Count | Should -Be 0
    }

    It 'vraie erreur enumeration ajoute VerificationErrors' {
        Mock Get-Process {
            $ex = New-Object System.UnauthorizedAccessException 'access denied'
            $err = [System.Management.Automation.ErrorRecord]::new(
                $ex,
                'AccessDenied,Microsoft.PowerShell.Commands.GetProcessCommand',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                'pwsh'
            )
            $PSCmdlet.WriteError($err)
        } -ParameterFilter { $Name -eq 'pwsh' -and $ErrorAction -eq 'SilentlyContinue' }

        $null = Get-FreshUninstallProcessListByName -Name 'pwsh'
        $script:FreshUninstallVerificationErrors.Count | Should -BeGreaterThan 0
        ($script:FreshUninstallVerificationErrors[0] | Out-String) | Should -Match 'enumeration processus pwsh'
    }
}

Describe 'Raccourcis Fresh (I2)' {
    It 'cible sous FreshRoot et Arguments vide reconnue' {
        $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("fw-lnk-{0}" -f [guid]::NewGuid().ToString('N'))
        $fresh = Join-Path $sandbox 'FreshWindows'
        New-Item -ItemType Directory -Path $fresh -Force | Out-Null
        $target = Join-Path $fresh 'Launch-FreshWindows.ps1'
        try {
            Resolve-FreshUninstallShortcutOwnership -LnkPath (Join-Path $fresh 'FreshWindows.lnk') -FreshRoot $fresh -Target $target -Arguments '' | Should -Be 'owned'
        }
        finally {
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'cible vide reste unknown' {
        $fresh = Join-Path ([System.IO.Path]::GetTempPath()) 'FreshWindows'
        Resolve-FreshUninstallShortcutOwnership -LnkPath 'C:\Users\Public\Desktop\FreshWindows.lnk' -FreshRoot $fresh -Target '' -Arguments '' | Should -Be 'unknown'
    }

    It 'homonyme tiers hors FreshRoot conserve foreign' {
        $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("fw-lnk-{0}" -f [guid]::NewGuid().ToString('N'))
        $fresh = Join-Path $sandbox 'FreshWindows'
        New-Item -ItemType Directory -Path $fresh -Force | Out-Null
        $other = Join-Path $sandbox 'OtherVendor\Launch-FreshWindows.ps1'
        New-Item -ItemType Directory -Path (Split-Path $other -Parent) -Force | Out-Null
        New-Item -ItemType File -Path $other -Force | Out-Null
        try {
            Resolve-FreshUninstallShortcutOwnership -LnkPath (Join-Path $fresh 'FreshWindows.lnk') -FreshRoot $fresh -Target $other -Arguments '' | Should -Be 'foreign'
        }
        finally {
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Contrats collections et PID CSV' {
    It 'return [object[]] vide => Count 0 (regression ,@)' {
        function Get-FreshWrappedTargetsSample {
            $out = [System.Collections.ArrayList]@()
            return [object[]]($out.ToArray())
        }
        @(Get-FreshWrappedTargetsSample).Count | Should -Be 0
    }

    It 'verification sans processus ne fabrique pas de faux PID vide' {
        $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("FreshWindows-EmptyProc-{0}" -f [guid]::NewGuid().ToString('N'))
        $fresh = Join-Path $sandbox 'FreshWindows'
        New-Item -ItemType Directory -Path $fresh -Force | Out-Null
        $script:FreshUninstallVerificationErrors = [System.Collections.ArrayList]@()
        $script:FreshUninstallProcessEnumeratorOverride = { return @() }
        $script:FreshUninstallTaskSnapshotOverride = {
            $list = [System.Collections.ArrayList]@()
            return [pscustomobject]@{ Ok = $true; Tasks = @($list.ToArray()); Error = '' }
        }
        try {
            $v = Get-FreshUninstallVerification -FreshRoot $fresh
            ($v.Issues -join ' ') | Should -Not -Match 'Processus encore actif :\s+\s*$'
            ($v.Issues | Where-Object { $_ -match 'Processus encore actif' }).Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            $script:FreshUninstallTaskSnapshotOverride = $null
        }
    }

    It 'Import-FreshUninstallImmuneIdsFromCsv decode plusieurs PID' {
        $script:FreshUninstallImmunePids = @{}
        Import-FreshUninstallImmuneIdsFromCsv -Csv '1001,1002,1003'
        Test-FreshUninstallProcessImmune -ProcessId 1001 -CommandLine '' | Should -Be $true
        Test-FreshUninstallProcessImmune -ProcessId 1002 -CommandLine '' | Should -Be $true
        Test-FreshUninstallProcessImmune -ProcessId 1003 -CommandLine '' | Should -Be $true
        Test-FreshUninstallProcessImmune -ProcessId 1004 -CommandLine '' | Should -Be $false
    }

    It 'Get-FreshWindowsUninstallImmuneProcessIds est plat (pas tableau imbrique)' {
        $ids = @(Get-FreshWindowsUninstallImmuneProcessIds)
        $ids.Count | Should -BeGreaterThan 0
        foreach ($id in $ids) {
            $id.GetType().FullName | Should -Be 'System.Int32'
        }
    }
}

Describe 'Uninstall-FreshWindows helpers' {
    It 'script tiers homonyme refuse si -File hors FreshRoot' {
        $fresh = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'FreshWindows')
        $otherScript = 'C:\Other\Launch-GameModeKill.ps1'
        $cmd = "powershell -File `"$otherScript`" -Arg `"$fresh\data`""
        Test-FreshUninstallCommandTargetsFreshRoot -CommandLine $cmd -FreshRoot $fresh | Should -Be $false
    }

    It 'fw-test dans sandbox GUID exclu sans marqueur' {
        $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("fw-sandbox-{0}" -f [guid]::NewGuid().ToString('N'))
        $d = Join-Path $sandbox 'fw-test-owned'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $saved = $env:TEMP
        $env:TEMP = $sandbox
        try {
            $inv = Get-FreshUninstallTempTestDirInventory
            ($inv.Unowned -contains $d) | Should -Be $true
        }
        finally {
            $env:TEMP = $saved
            Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
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
}

Describe 'Staging menu DryRun' {
    It 'Remove-FreshWindowsUninstallRunStaging verifie la suppression' {
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("FreshWindows-UninstallRun-{0}" -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        Remove-FreshWindowsUninstallRunStaging -StageDir $stage | Should -Be $true
        Test-Path -LiteralPath $stage | Should -Be $false
    }
}

Describe 'launcher menu desinstallation' {
    It 'menu 12 epoch 60' {
        $lines = Get-Content -LiteralPath $script:LauncherPath -Encoding UTF8 -Raw
        $lines | Should -Match '12  Desinstallation'
        $lines | Should -Match 'FreshWindowsLibEpoch = 60'
    }

    It 'ImmuneProcessIdsCsv dans Launcher-Core' {
        $core = Get-Content -LiteralPath $script:LauncherCore -Encoding UTF8 -Raw
        $core | Should -Match 'ImmuneProcessIdsCsv'
    }
}

Describe 'Confirm-FreshWindowsUninstallAction' {
    It 'refuse oui espaces et ok' {
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
