#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Remove-FreshWindowsObsoleteLocalAssets' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        $script:RepoRoot = $root
        . (Join-Path $root 'scripts/lib/Launcher-Core.ps1')

        $tempRoot = $env:TEMP
        if ([string]::IsNullOrWhiteSpace($tempRoot) -or $tempRoot -match '^:') {
            $tempRoot = if ($env:TMP -and $env:TMP -notmatch '^:') { $env:TMP } else { '/tmp' }
        }
        $script:GuidRoot = Join-Path $tempRoot ('fw-obsolete-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:GuidRoot -Force | Out-Null
        $script:FreshRoot = Join-Path $script:GuidRoot 'FreshWindows'
        New-Item -ItemType Directory -Path $script:FreshRoot -Force | Out-Null
        $env:LOCALAPPDATA = $script:GuidRoot
    }

    AfterAll {
        $env:LOCALAPPDATA = $script:OrigLocalAppData
        if ($script:GuidRoot -and (Test-Path -LiteralPath $script:GuidRoot)) {
            Remove-Item -LiteralPath $script:GuidRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'restaure LOCALAPPDATA apres le describe' {
        $env:LOCALAPPDATA | Should -Be $script:GuidRoot
    }

    It 'refuse un chemin hors LOCALAPPDATA\FreshWindows' {
        $bogus = Join-Path $script:GuidRoot 'NotFresh'
        New-Item -ItemType Directory -Path $bogus -Force | Out-Null
        $r = Remove-FreshWindowsObsoleteLocalAssets -FreshAppData $bogus
        $r.ok | Should -Be $false
        $r.errors | Should -Not -BeNullOrEmpty
    }

    It 'refuse FreshWindowsOld (derive du nom canonique)' {
        $old = Join-Path $script:GuidRoot 'FreshWindowsOld'
        New-Item -ItemType Directory -Path $old -Force | Out-Null
        $r = Remove-FreshWindowsObsoleteLocalAssets -FreshAppData $old
        $r.ok | Should -Be $false
    }

    It 'supprime IA/voix mais garde maintenance systray' {
        $watch = Join-Path $script:FreshRoot 'GameMode-WatchAgent.ps1'
        $prefs = Join-Path $script:FreshRoot 'watch-agent-user.json'
        $weekly = Join-Path $script:FreshRoot 'weekly-health-last.json'
        $ai = Join-Path $script:FreshRoot 'agent-ai.user.json'
        $aiDir = Join-Path $script:FreshRoot 'ai'
        New-Item -ItemType Directory -Path $aiDir -Force | Out-Null
        Set-Content -LiteralPath $watch -Value '# watch' -Encoding UTF8
        Set-Content -LiteralPath $prefs -Value '{"monitorEnabled":true}' -Encoding UTF8
        Set-Content -LiteralPath $weekly -Value '{"at":"2026-01-01"}' -Encoding UTF8
        Set-Content -LiteralPath $ai -Value '{"enabled":true}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $aiDir 'dummy.ps1') -Value '1' -Encoding UTF8

        $r = Remove-FreshWindowsObsoleteLocalAssets -FreshAppData $script:FreshRoot
        $r.ok | Should -Be $true

        Test-Path -LiteralPath $watch | Should -Be $true
        Test-Path -LiteralPath $prefs | Should -Be $true
        Test-Path -LiteralPath $weekly | Should -Be $true
        Test-Path -LiteralPath $ai | Should -Be $false
        Test-Path -LiteralPath $aiDir | Should -Be $false
    }
}

Describe 'FreshWindows lib epoch alignment' {
    It 'launcher et Launcher-Core partagent la meme epoch' {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        $launcher = Get-Content -LiteralPath (Join-Path $root 'launcher.ps1') -Raw
        $core = Get-Content -LiteralPath (Join-Path $root 'scripts/lib/Launcher-Core.ps1') -Raw
        if ($launcher -match 'FreshWindowsLibEpoch\s*=\s*(\d+)') {
            $le = $Matches[1]
        }
        else { throw 'epoch launcher introuvable' }
        if ($core -match 'FreshWindowsLibEpoch\s*=\s*(\d+)') {
            $ce = $Matches[1]
        }
        else { throw 'epoch core introuvable' }
        $le | Should -Be $ce
        $le | Should -Be '61'
    }
}
