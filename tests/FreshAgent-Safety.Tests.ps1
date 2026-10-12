#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'FreshAgent safety' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        $script:RepoRoot = $root
        . (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
        . (Join-Path $root 'scripts\lib\FreshAgent-SkillsEngine.ps1')
        . (Join-Path $root 'scripts\lib\FreshAgent-Confirm.ps1')
        . (Join-Path $root 'scripts\lib\FreshAgent-ActionLog.ps1')
        . (Join-Path $root 'scripts\lib\FreshAgent-WindowsActions.ps1')
        . (Join-Path $root 'scripts\lib\FreshAgent-Optimize.ps1')
        . (Join-Path $root 'scripts\ai\FreshAgent-OllamaBridge.ps1')

        $script:Tmp = Join-Path $env:TEMP ('FreshAgent-Safety-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:Tmp 'configs\skills\system') -Force | Out-Null
        $reg = @{
            schemaVersion = 1
            skills        = @(
                @{ id = 'close_app'; file = 'system/close_app.json'; enabled = $true },
                @{ id = 'game_session'; file = 'system/game_session.json'; enabled = $true },
                @{ id = 'cleanup'; file = 'system/cleanup.json'; enabled = $true },
                @{ id = 'create_restore_point'; file = 'system/create_restore_point.json'; enabled = $true }
            )
        }
        $reg | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $script:Tmp 'configs\skills\registry.json') -Encoding UTF8
        foreach ($name in @('close_app.json', 'game_session.json', 'cleanup.json', 'create_restore_point.json')) {
            Copy-Item -LiteralPath (Join-Path $root "configs\skills\system\$name") -Destination (Join-Path $script:Tmp "configs\skills\system\$name") -Force
        }
    }

    AfterAll {
        if ($script:Tmp -and (Test-Path -LiteralPath $script:Tmp)) {
            Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'parses bool strings (false is not true)' {
        ConvertTo-FreshAgentBool -Value 'false' | Should -Be $false
        ConvertTo-FreshAgentBool -Value 'true' | Should -Be $true
        ConvertTo-FreshAgentBool -Value 'oui' | Should -Be $true
        ConvertTo-FreshAgentBool -Value 'non' | Should -Be $false
        ConvertTo-FreshAgentBool -Value '0' | Should -Be $false
        ConvertTo-FreshAgentBool -Value $false | Should -Be $false
        ConvertTo-FreshAgentBool -Value $null -Default $true | Should -Be $true
    }

    It 'cleanup recycle bin defaults to opt-in' {
        # Sous PS 5.1, Get-Command.ScriptBlock.Ast.ParamBlock est vide pour ce param().
        $src = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts\lib\FreshAgent-Optimize.ps1') -Raw
        $src | Should -Match '(?m)function\s+Invoke-SkillCleanup\b'
        $src | Should -Match '(?m)\$RecycleBin\s*=\s*\$false'
        $src | Should -Not -Match '(?m)\[bool\]\s*\$RecycleBin'
    }

    It 'pending confirm expires and a later ok does nothing' {
        $pending = Set-FreshAgentPendingConfirm -SkillId 'system_power' -Parameters @{ Action = 'shutdown' } `
            -Prompt 'eteindre' -FreshAppData $script:Tmp -RepoRef 'main' -Source 'test'
        $pending.skillId | Should -Be 'system_power'
        $live = Get-FreshAgentPendingConfirm -FreshAppData $script:Tmp
        $live.skillId | Should -Be 'system_power'

        $path = Get-FreshAgentPendingConfirmPath -FreshAppData $script:Tmp
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $raw.at = (Get-Date).AddSeconds(-90).ToString('o')
        $raw | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8

        $expired = Get-FreshAgentPendingConfirm -FreshAppData $script:Tmp
        $expired | Should -BeNullOrEmpty
        Test-Path -LiteralPath $path | Should -Be $false

        $done = Complete-FreshAgentPendingConfirm -Decision confirm -FreshAppData $script:Tmp
        $done.ok | Should -Be $false
        $done.message | Should -Match 'attente'
    }

    It 'close_app asks confirmation naming the process and does not kill yet' {
        $skill = Get-Content -LiteralPath (Join-Path $script:Tmp 'configs\skills\system\close_app.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        (Test-FreshAgentSkillRequiresConfirm -Skill $skill) | Should -Be $true

        function script:Resolve-FreshAgentSpokenAppName {
            param([string]$Name, [string]$FreshAppData)
            return $Name
        }
        $ping = Join-Path $env:SystemRoot 'System32\ping.exe'
        $p = Start-Process -FilePath $ping -ArgumentList @('-n', '40', '127.0.0.1') -WindowStyle Hidden -PassThru
        try {
            $alive = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
            $alive | Should -Not -BeNullOrEmpty
            $r = Invoke-FreshAgentSkill -SkillId 'close_app' -Parameters @{ name = 'ping' } `
                -RepoRef 'main' -FreshAppData $script:Tmp -Source 'test'
            $r.pendingConfirm | Should -Be $true
            $r.message | Should -Match 'ping'
            $r.spoken | Should -Match 'ping'
            $r.message | Should -Match ([regex]::Escape([string]$p.Id))
            Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
        finally {
            if ($p -and -not $p.HasExited) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
            Clear-FreshAgentPendingConfirm -FreshAppData $script:Tmp
        }
    }

    It 'close matching does not fuzzy-contain unrelated processes' {
        Test-FreshAgentCloseProcessNameMatch -ProcessName 'Discord' -Candidates @('discord') | Should -Be $true
        Test-FreshAgentCloseProcessNameMatch -ProcessName 'chrome' -Candidates @('chrome') | Should -Be $true
        Test-FreshAgentCloseProcessNameMatch -ProcessName 'Code' -Candidates @('vscode') | Should -Be $false
        Test-FreshAgentCloseProcessNameMatch -ProcessName 'SearchIndexer' -Candidates @('code') | Should -Be $false
        Test-FreshAgentCloseProcessNameMatch -ProcessName 'notepad' -Candidates @('note') | Should -Be $false
    }

    It 'game_session requires confirmation' {
        $skill = Get-Content -LiteralPath (Join-Path $script:Tmp 'configs\skills\system\game_session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        (Test-FreshAgentSkillRequiresConfirm -Skill $skill) | Should -Be $true
        [string]$skill.confirmPrompt | Should -Match 'processus'
    }

    It 'requiresAdmin is enforced when the session is not elevated' {
        $skill = Get-Content -LiteralPath (Join-Path $script:Tmp 'configs\skills\system\create_restore_point.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        (Test-FreshAgentSkillRequiresAdmin -Skill $skill) | Should -Be $true
        (Test-FreshAgentSkillRequiresAdmin -Skill ([pscustomobject]@{ requiresAdmin = 'false' })) | Should -Be $false
        if (-not (Test-FreshAgentIsElevated)) {
            $r = Invoke-FreshAgentSkill -SkillId 'create_restore_point' -Parameters @{} `
                -RepoRef 'main' -FreshAppData $script:Tmp -Source 'test'
            $r.ok | Should -Be $false
            $r.message | Should -Match 'administrateur'
        }
    }

    It 'content stamp ignores dev mode and notices epoch changes' {
        (Test-FreshAgentContentStampStale -StoredRef 'local-dev' -LocalEpoch '' -RemoteEpoch '47' -RepoRef 'main') | Should -Be $false
        (Test-FreshAgentContentStampStale -StoredRef 'main' -LocalEpoch '' -RemoteEpoch '47' -RepoRef 'main') | Should -Be $true
        (Test-FreshAgentContentStampStale -StoredRef 'main' -LocalEpoch '46' -RemoteEpoch '47' -RepoRef 'main') | Should -Be $true
        (Test-FreshAgentContentStampStale -StoredRef 'main' -LocalEpoch '47' -RemoteEpoch '47' -RepoRef 'main') | Should -Be $false
        (Test-FreshAgentContentStampStale -StoredRef 'main' -LocalEpoch '47' -RemoteEpoch '' -RepoRef 'main') | Should -Be $false
    }

    It 'idle suggestion calls UserPrompt without tools and off the caller' {
        $src = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts\lib\FreshAgent-IdleSuggest.ps1') -Raw
        $src | Should -Match 'Invoke-FreshAgentAiTurn -UserPrompt'
        $src | Should -Not -Match 'Invoke-FreshAgentAiTurn -Prompt '
        $src | Should -Match '-NoTools'
        $src | Should -Match 'Start-Process'
        (Get-Command Invoke-FreshAgentAiTurn).Parameters.ContainsKey('UserPrompt') | Should -Be $true
        (Get-Command Invoke-FreshAgentAiTurn).Parameters.ContainsKey('NoTools') | Should -Be $true
    }

    It 'skill background script escapes null and loads GameMode-Common' {
        $src = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts\GameMode-WatchAgent.ps1') -Raw
        $src | Should -Match '(?m)^\s*`\$spoken = `\$null\s*$'
        @([regex]::Matches($src, 'GameMode-Common\.ps1')).Count | Should -BeGreaterThan 2
    }
}
