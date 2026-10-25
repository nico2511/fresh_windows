#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Appx bloatware classification' {
    BeforeAll {
        if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = if ($env:TEMP) { $env:TEMP } else { '/tmp' } }
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        $script:RepoRoot = $root
        . (Join-Path $root 'scripts\lib\FreshWindows-AppxBloatware.ps1')
        $script:Config = Get-FreshWindowsAppxBloatwareConfig -RepoRoot $root
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

    It 'marks Acer Configuration Manager as confirm later' {
        (Get-FreshWindowsAppxBloatwareClassification -PackageIdentity 'Acer.AcerConfigurationManager' -Config $script:Config) |
            Should -Be 'ConfirmLater'
    }

    It 'dry-run does not call remove cmdlets' {
        $plan = Invoke-FreshWindowsAppxBloatwareCleanup -RepoRoot $script:RepoRoot -PackageIdentities @(
            'Microsoft.BingNews',
            'Microsoft.Paint',
            'Unknown.PersonalApp'
        )
        $plan.dryRun | Should -Be $true
        $plan.toRemove | Should -Contain 'Microsoft.BingNews'
        $plan.protected | Should -Contain 'Microsoft.Paint'
        $plan.unknown | Should -Contain 'Unknown.PersonalApp'
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
