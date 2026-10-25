#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'FreshWindows background audit' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        $script:RepoRoot = $root
        . (Join-Path $root 'scripts\lib\FreshWindows-BackgroundAudit.ps1')
        $script:Tmp = Join-Path $env:TEMP ('FreshBgAudit-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null
    }

    AfterAll {
        if ($script:Tmp -and (Test-Path -LiteralPath $script:Tmp)) {
            Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'catalog lists only known Fresh scheduled task names' {
        $names = @(Get-FreshWindowsBackgroundTaskNames)
        $names.Count | Should -Be 4
        $names | Should -Contain 'FreshWindows-WatchAgent'
        Test-FreshWindowsScheduledTaskIsFresh -TaskName 'FreshWindows-WingetUpgrade' | Should -Be $true
        Test-FreshWindowsScheduledTaskIsFresh -TaskName 'MicrosoftEdgeUpdateTaskMachineCore' | Should -Be $false
        { Get-FreshWindowsBackgroundScheduledTaskState -TaskName 'MicrosoftEdgeUpdateTaskMachineCore' } |
            Should -Throw '*hors perimetre*'
    }

    It 'read-only audit does not create journal entries' {
        $journal = Join-Path $script:Tmp 'background-audit-journal.jsonl'
        if (Test-Path -LiteralPath $journal) { Remove-Item -LiteralPath $journal -Force }
        $r = Invoke-FreshWindowsBackgroundAudit -FreshAppData $script:Tmp -ReportPath (Join-Path $script:Tmp 'r.txt')
        $r.mode | Should -Be 'read-only'
        Test-Path -LiteralPath $journal | Should -Be $false
        Test-Path -LiteralPath (Join-Path $script:Tmp 'r.txt') | Should -Be $true
    }

    It 'apply and restore are symmetric for prefs (mocked tasks)' {
        $disable = { param($tn) }
        $enable = { param($tn) }
        $targets = @('prefs-monitor-off', 'prefs-ai-off', 'prefs-voice-off')
        $r1 = Invoke-FreshWindowsBackgroundAudit -Apply -NoConfirm -TargetIds $targets `
            -FreshAppData $script:Tmp -ScheduledTaskDisable $disable -ScheduledTaskEnable $enable
        $r1.mode | Should -Be 'apply'
        ($r1.results | Where-Object { $_.ok }).Count | Should -Be 3

        $watchPath = Join-Path $script:Tmp 'watch-agent-user.json'
        $aiPath = Join-Path $script:Tmp 'agent-ai.user.json'
        (Get-Content -LiteralPath $watchPath -Raw | ConvertFrom-Json).monitorEnabled | Should -Be $false
        (Get-Content -LiteralPath $aiPath -Raw | ConvertFrom-Json).enabled | Should -Be $false
        (Get-Content -LiteralPath $aiPath -Raw | ConvertFrom-Json).voice.enabled | Should -Be $false

        $rr = Restore-FreshWindowsBackgroundFromJournal -FreshAppData $script:Tmp -ScheduledTaskEnable $enable
        $rr.ok | Should -Be $true

        (Get-Content -LiteralPath $watchPath -Raw | ConvertFrom-Json).monitorEnabled | Should -Be $true
        (Get-Content -LiteralPath $aiPath -Raw | ConvertFrom-Json).enabled | Should -Be $false
        (Get-Content -LiteralPath $aiPath -Raw | ConvertFrom-Json).voice.enabled | Should -Be $false
    }

    It 'rejects scheduled task names outside Fresh catalog' {
        { Get-FreshWindowsBackgroundScheduledTaskState -TaskName 'Microsoft\Windows\Defrag\ScheduledDefrag' } |
            Should -Throw '*hors perimetre*'
    }

    It 'Resolve-FreshWindowsKnownProcessRole ignore chemins AppData generiques' {
        $appdata = 'C:\Users\x\AppData\Local\FreshWindows'
        Resolve-FreshWindowsKnownProcessRole -CommandLine "wt.exe -d $appdata" -ProcessName 'WindowsTerminal.exe' |
            Should -Be $null
        Resolve-FreshWindowsKnownProcessRole -CommandLine "powershell -File $appdata\Invoke-FreshWindowsBackgroundAudit.ps1" `
            -ProcessName 'powershell.exe' -FreshAppData $appdata | Should -Be $null
        Resolve-FreshWindowsKnownProcessRole -CommandLine 'powershell -STA -File GameMode-WatchAgent.ps1' `
            -ProcessName 'powershell.exe' | Should -Be 'agent systray'
        Resolve-FreshWindowsKnownProcessRole -CommandLine 'FreshAgent-BackgroundWorker.ps1 -Action Rag' `
            -ProcessName 'powershell.exe' | Should -Be 'worker'
    }

    It 'reconnait Launch-GameModeWatch.ps1 (ligne de commande reelle systray)' {
        $cmd = '"C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe"  -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\Nico\AppData\Local\FreshWindows\Launch-GameModeWatch.ps1"'
        Resolve-FreshWindowsKnownProcessRole -CommandLine $cmd -ProcessName 'powershell.exe' |
            Should -Be 'agent systray'
    }

    It 'associe un enfant sans CommandLine au parent Fresh (enfant agent)' {
        Get-FreshWindowsFreshChildProcessRole -ParentRole 'agent systray' | Should -Be 'enfant agent'
        Get-FreshWindowsFreshChildProcessRole -ParentRole 'worker' | Should -Be 'enfant worker'
        Resolve-FreshWindowsKnownProcessRole -CommandLine '' -ProcessName 'powershell.exe' | Should -Be $null
    }

    It 'Test-FreshWindowsIsHostTerminalProcess detecte Windows Terminal' {
        Test-FreshWindowsIsHostTerminalProcess -ProcessName 'WindowsTerminal.exe' | Should -Be $true
        Test-FreshWindowsIsHostTerminalProcess -ProcessName 'powershell.exe' | Should -Be $false
    }
}
