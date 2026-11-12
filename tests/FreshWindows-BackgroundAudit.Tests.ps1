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
        . (Join-Path $root 'scripts/lib/FreshWindows-BackgroundAudit.ps1')
        $tempRoot = $env:TEMP
        if ([string]::IsNullOrWhiteSpace($tempRoot) -or $tempRoot -match '^:') {
            $tempRoot = if ($env:TMP -and $env:TMP -notmatch '^:') { $env:TMP } else { '/tmp' }
        }
        $script:Tmp = Join-Path $tempRoot ('FreshBgAudit-{0}' -f [guid]::NewGuid().ToString('N'))
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

    It 'apply and restore are symmetric for scheduled tasks (mocked)' {
        $script:DisableCalls = [System.Collections.ArrayList]@()
        $script:EnableCalls = [System.Collections.ArrayList]@()
        $disable = {
            param($tn)
            [void]$script:DisableCalls.Add([string]$tn)
        }
        $enable = {
            param($tn)
            [void]$script:EnableCalls.Add([string]$tn)
        }
        $script:MockTaskState = @{ present = $true; state = 'Ready'; lastRun = $null; nextRun = $null }
        function Get-FreshWindowsBackgroundScheduledTaskState {
            param([Parameter(Mandatory)][string]$TaskName)
            if (-not (Test-FreshWindowsScheduledTaskIsFresh -TaskName $TaskName)) {
                throw "Tache hors perimetre Fresh Windows : $TaskName"
            }
            return $script:MockTaskState
        }

        $r1 = Invoke-FreshWindowsBackgroundCatalogApply -TargetId 'scheduled-task-winutil' `
            -FreshAppData $script:Tmp -ScheduledTaskDisable $disable -ScheduledTaskEnable $enable
        $r1.ok | Should -Be $true
        $script:DisableCalls | Should -Contain 'FreshWindows-WinUtilReapply'

        $rr = Restore-FreshWindowsBackgroundFromJournal -FreshAppData $script:Tmp -ScheduledTaskEnable $enable
        $rr.ok | Should -Be $true
        @($rr.results).Count | Should -Be 1
        $script:EnableCalls | Should -Contain 'FreshWindows-WinUtilReapply'
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
            -ProcessName 'powershell.exe' -FreshAppData $appdata | Should -Be 'maintenance'
    }
}
