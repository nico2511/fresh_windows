#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-Health.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-Confirm.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-ActionLog.ps1')

Describe 'FreshAgent Health + Confirm' {
    It 'Rejects kill when process name mismatches (PID recycle guard)' {
        $current = Get-Process -Id $PID
        $r = Stop-FreshAgentProcessVerified -ProcessId $PID -ProcessName 'DefinitelyNotThisProcess'
        $r.ok | Should -Be $false
        $r.message | Should -Match 'recycle|attendu'
        $still = Get-Process -Id $PID -ErrorAction SilentlyContinue
        $still | Should -Not -BeNullOrEmpty
        $still.ProcessName | Should -Be $current.ProcessName
    }

    It 'Resolves confirm utterances' {
        Resolve-FreshAgentConfirmUtterance -Transcript 'oui' | Should -Be 'confirm'
        Resolve-FreshAgentConfirmUtterance -Transcript 'annule' | Should -Be 'cancel'
        Resolve-FreshAgentConfirmUtterance -Transcript 'lance steam' | Should -Be $null
    }

    It 'Writes action log entries' {
        $tmp = Join-Path $env:TEMP ('FreshAgent-ActionLog-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Add-FreshAgentActionLogEntry -Action 'test' -SkillId 'x' -Message 'hello' -FreshAppData $tmp
        $recent = Get-FreshAgentActionLogRecent -Count 5 -FreshAppData $tmp
        $recent.Count | Should -BeGreaterThan 0
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}
