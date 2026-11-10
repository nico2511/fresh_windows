#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Appx bloatware classification' {
    BeforeAll {
        function global:Remove-AppxPackage { param($Package) throw 'Remove-AppxPackage doit etre mocke dans les tests' }
        function global:Remove-AppxProvisionedPackage { param($Online, $PackageName) throw 'Remove-AppxProvisionedPackage doit etre mocke' }
        function global:Checkpoint-Computer { throw 'Checkpoint-Computer ne doit pas etre appele en test' }
        function global:Enable-ComputerRestore { param($Drive) return $true }

        $script:OrigLocalAppData = $env:LOCALAPPDATA
        $tempRoot = if ($env:TEMP -and $env:TEMP -notmatch '^:') { $env:TEMP } else { '/tmp' }
        $script:GuidRoot = Join-Path $tempRoot ('fw-appx-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:GuidRoot 'FreshWindows') -Force | Out-Null
        $env:LOCALAPPDATA = $script:GuidRoot
        $script:FreshRoot = Join-Path $script:GuidRoot 'FreshWindows'

        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        $script:RepoRoot = $root
        . (Join-Path $root 'scripts\lib\FreshWindows-AppxBloatware.ps1')
        $script:Config = Get-FreshWindowsAppxBloatwareConfig -RepoRoot $root -FreshAppData $script:FreshRoot
    }

    AfterAll {
        $env:LOCALAPPDATA = $script:OrigLocalAppData
        if ($script:GuidRoot -and (Test-Path -LiteralPath $script:GuidRoot)) {
            Remove-Item -LiteralPath $script:GuidRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'classifies protected Paint classic and remove Paint 3D' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Microsoft.Paint' -Config $script:Config) |
            Should -Be 'Protected'
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Microsoft.MSPaint' -Config $script:Config) |
            Should -Be 'Remove'
    }

    It 'never classifies unknown packages as Remove' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Contoso.UnknownApp' -Config $script:Config) |
            Should -Be 'Unknown'
    }

    It 'protected wins over remove list' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Microsoft.WindowsStore_8wekyb3d8bbwe' -Config $script:Config) |
            Should -Be 'Protected'
    }

    It 'treats unlisted OEM packages as unknown (never removed)' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Contoso.OemConfigurationManager' -Config $script:Config) |
            Should -Be 'Unknown'
    }

    It 'classifies remove.oem entries as Remove' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'DolbyLaboratories.DolbyAccess' -Config $script:Config) |
            Should -Be 'Remove'
    }

    It 'removes Xbox Game Bar overlay but protects Xbox app and Gaming Services' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Microsoft.XboxGamingOverlay' -Config $script:Config) |
            Should -Be 'Remove'
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Microsoft.GamingApp' -Config $script:Config) |
            Should -Be 'Protected'
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Microsoft.GamingServices' -Config $script:Config) |
            Should -Be 'Protected'
    }

    It 'dry-run lists unknown packages as add candidates' {
        $plan = Invoke-FreshWindowsAppxBloatwareCleanup -RepoRoot $script:RepoRoot -FreshAppData $script:FreshRoot -PackageIdentities @(
            'Microsoft.BingNews',
            'Microsoft.Paint',
            'Unknown.PersonalApp'
        )
        $plan.dryRun | Should -Be $true
        $plan.toRemove | Should -Contain 'Microsoft.BingNews'
        $plan.protected | Should -Contain 'Microsoft.Paint'
        $plan.addCandidates | Should -Contain 'Unknown.PersonalApp'
        $plan.message | Should -Match 'Candidats a ajouter'
        $plan.logPath | Should -Match ([regex]::Escape($script:FreshRoot))
    }

    It 'Apply never removes unknown packages and skips restore point' {
        $script:AppxRemoved = [System.Collections.ArrayList]@()
        $script:RestorePointCalls = 0
        function global:Remove-AppxPackage {
            param($Package)
            [void]$script:AppxRemoved.Add([string]$Package)
            return $true
        }
        function global:Get-AppxPackage {
            param([switch]$AllUsers, [string]$Name)
            if ($Name) {
                if ($Name -eq 'Microsoft.BingNews') {
                    return [pscustomobject]@{ Name = 'Microsoft.BingNews'; PackageFullName = 'Microsoft.BingNews_8wekyb3d8bbwe' }
                }
                return $null
            }
            return @(
                [pscustomobject]@{ Name = 'Microsoft.BingNews'; PackageFullName = 'Microsoft.BingNews_8wekyb3d8bbwe' }
            )
        }
        function global:New-FreshWindowsAppxBloatwareRestorePoint {
            $script:RestorePointCalls++
            throw 'restore point should be skipped'
        }
        $result = Invoke-FreshWindowsAppxBloatwareCleanup -Apply -SkipRestorePoint -RepoRoot $script:RepoRoot -FreshAppData $script:FreshRoot -PackageIdentities @(
            'Contoso.UnknownApp',
            'Microsoft.BingNews'
        )
        $result.dryRun | Should -Be $false
        $result.removed | Should -Not -Contain 'Contoso.UnknownApp'
        @($result.addCandidates) | Should -Contain 'Contoso.UnknownApp'
        $script:AppxRemoved | Should -Not -BeNullOrEmpty
        $script:RestorePointCalls | Should -Be 0
    }

    It 'prefix rules match king.com family' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'king.com.CandyCrushSaga' -Config $script:Config) |
            Should -Be 'Remove'
    }

    It 'suffix rule protects cw5n1h2txyewy packages' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy' -Config $script:Config) |
            Should -Be 'Protected'
    }
}
