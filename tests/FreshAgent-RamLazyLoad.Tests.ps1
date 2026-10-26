#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Fresh Agent RAM / lazy-load' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        $script:RepoRoot = $root
        . (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
        $script:Tmp = Join-Path $env:TEMP ('FreshRamLazy-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null
        $script:FreshAppData = $script:Tmp
        $libDir = Join-Path $script:Tmp 'lib'
        New-Item -ItemType Directory -Path $libDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'scripts\lib\FreshAgent-Log.ps1') -Destination (Join-Path $libDir 'FreshAgent-Log.ps1') -Force
        Copy-Item -LiteralPath (Join-Path $root 'scripts\lib\FreshAgent-Optimize.ps1') -Destination (Join-Path $libDir 'FreshAgent-Optimize.ps1') -Force
        New-Item -ItemType Directory -Path (Join-Path $script:Tmp 'ai') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'scripts\ai\FreshAgent-VoiceWorker.ps1') -Destination (Join-Path $script:Tmp 'ai\FreshAgent-VoiceWorker.ps1') -Force
        Copy-Item -LiteralPath (Join-Path $root 'scripts\lib\FreshAgent-SttSettings.ps1') -Destination (Join-Path $libDir 'FreshAgent-SttSettings.ps1') -Force
        Copy-Item -LiteralPath (Join-Path $root 'scripts\lib\FreshAgent-WindowsActions.ps1') -Destination (Join-Path $libDir 'FreshAgent-WindowsActions.ps1') -Force
        foreach ($rel in (Get-FreshAgentMinimalBootModuleList)) {
            $name = Split-Path $rel -Leaf
            $src = Join-Path $root ('scripts\' + ($rel -replace '/', '\'))
            if (Test-Path -LiteralPath $src) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $libDir $name) -Force
            }
        }
    }

    BeforeEach {
        if (Get-Command Reset-FreshAgentLibLoadRegistry -ErrorAction SilentlyContinue) {
            Reset-FreshAgentLibLoadRegistry
        }
        else {
            $script:FreshAgentLibsLoaded = @{}
        }
    }

    AfterAll {
        if ($script:Tmp -and (Test-Path -LiteralPath $script:Tmp)) {
            Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Import-FreshAgentLibOnce ne recharge pas une lib deja chargee' {
        Test-FreshAgentLibLoaded -RelativePath 'lib/FreshAgent-Log.ps1' | Should -Be $false
        $ok1 = Import-FreshAgentLibOnce -RelativePath 'lib/FreshAgent-Log.ps1' -FreshAppData $script:FreshAppData
        $ok2 = Import-FreshAgentLibOnce -RelativePath 'lib/FreshAgent-Log.ps1' -FreshAppData $script:FreshAppData
        $ok1 | Should -Be $true
        $ok2 | Should -Be $true
        Test-FreshAgentLibLoaded -RelativePath 'lib/FreshAgent-Log.ps1' | Should -Be $true
        (Get-FreshAgentLibLoadRegistry).Count | Should -Be 1
    }

    It 'boot minimal ne charge pas VoiceWorker avant usage voix' {
        Import-FreshAgentMinimalBootModules -FreshAppData $script:FreshAppData
        Test-FreshAgentLibLoaded -RelativePath 'ai/FreshAgent-VoiceWorker.ps1' | Should -Be $false
        Test-FreshAgentLibLoaded -RelativePath 'ai/Ollama-Manager.ps1' | Should -Be $false
        Test-FreshAgentLibLoaded -RelativePath 'lib/FreshAgent-VoiceRouter.ps1' | Should -Be $false
        Test-FreshAgentLibLoaded -RelativePath 'lib/FreshAgent-Dashboard.ps1' | Should -Be $false
        Ensure-FreshAgentVoiceLibsLoaded -FreshAppData $script:FreshAppData | Out-Null
        $reg = Get-FreshAgentLibLoadRegistry
        $reg.ContainsKey('ai/freshagent-voiceworker.ps1') | Should -Be $true
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            Test-FreshAgentLibLoaded -RelativePath 'ai/FreshAgent-VoiceWorker.ps1' | Should -Be $true
            Get-Command Start-FreshAgentVoiceListenSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    It 'VoiceWorker charge via Import-FreshAgentFileIntoScriptScope (PSScriptRoot vide)' {
        $vwPath = Join-Path $script:FreshAppData 'ai\FreshAgent-VoiceWorker.ps1'
        Test-Path -LiteralPath $vwPath | Should -Be $true
        Test-FreshAgentLibLoaded -RelativePath 'ai/FreshAgent-VoiceWorker.ps1' | Should -Be $false
        Import-FreshAgentFileIntoScriptScope -LiteralPath $vwPath
        Get-Command Get-FreshAgentVoiceWorkerPaths -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        if ($IsWindows -or $env:OS -eq 'Windows_NT') {
            Get-Command Start-FreshAgentVoiceListenSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-FreshAgentWatchMemoryTrimEnabled lit watch-agent-user.json' {
        $p = Join-Path $script:Tmp 'watch-agent-user.json'
        @{ memoryTrimAfterInit = $false } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding UTF8
        Get-FreshAgentWatchMemoryTrimEnabled -FreshAppData $script:Tmp | Should -Be $false
        @{ memoryTrimAfterInit = $true } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding UTF8
        Get-FreshAgentWatchMemoryTrimEnabled -FreshAppData $script:Tmp | Should -Be $true
    }

    It 'agent-content epoch est 56' {
        $contentPath = Join-Path $script:RepoRoot 'configs\agent-content.json'
        $meta = Get-Content -LiteralPath $contentPath -Raw -Encoding UTF8 | ConvertFrom-Json
        [string]$meta.epoch | Should -Be '56'
    }

    It 'Format-FreshAgentWatchMemoryTrimBootLogLine inclut WS et prive en Mo' {
        $line = Format-FreshAgentWatchMemoryTrimBootLogLine -TrimResult @{
            ok = $true; skipped = $false; wsMbBefore = 185; wsMbAfter = 16; privateMbBefore = 150; privateMbAfter = 115
        }
        $line | Should -Match '^Module boot: memory trim ok=True WS 185->16 Mo, prive 150->115 Mo$'
        $skip = Format-FreshAgentWatchMemoryTrimBootLogLine -TrimResult @{ ok = $true; skipped = $true; message = 'memoryTrimAfterInit=false' }
        $skip | Should -Be 'Module boot: memory trim ignore (memoryTrimAfterInit=false)'
    }
}

Describe 'Fresh Agent poll timers (script inspection)' {
    BeforeAll {
        $script:RepoRootPoll = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        $script:WatchAgentSource = Get-Content -LiteralPath (Join-Path $script:RepoRootPoll 'scripts\GameMode-WatchAgent.ps1') -Raw -Encoding UTF8
    }

    It 'WatchPollTimer respecte monitorEnabled' {
        $script:WatchAgentSource | Should -Match 'function Sync-WatchAgentPollTimer'
        $script:WatchAgentSource | Should -Match 'if \(-not \$script:UserSettings\.monitorEnabled\) \{ return \}'
    }

    It 'FaSttPollTimer dispose quand voix OFF' {
        $script:WatchAgentSource | Should -Match 'function Stop-FreshAgentSttPollTimerIfRunning'
        $vw = Get-Content -LiteralPath (Join-Path $script:RepoRootPoll 'scripts\ai\FreshAgent-VoiceWorker.ps1') -Raw -Encoding UTF8
        $vw | Should -Match 'Stop-FreshAgentSttPollTimerIfRunning'
        $vw | Should -Match 'Stop-FreshAgentVoiceWatchTimerIfRunning'
    }
}
