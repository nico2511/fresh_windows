#Requires -Version 5.1
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-SttSettings.ps1')

Describe 'FreshAgent PTT state machine' {
    It 'keydown repeats produce a single start' {
        $state = New-FreshAgentPttMachineState
        $r1 = Update-FreshAgentPttMachine -State $state -KeyDown $true -Recording $false -Transcribing $false
        $r2 = Update-FreshAgentPttMachine -State $r1.State -KeyDown $true -Recording $true -Transcribing $false
        $r3 = Update-FreshAgentPttMachine -State $r2.State -KeyDown $true -Recording $true -Transcribing $false
        @($r1.Actions) | Should -Be @('start')
        @($r2.Actions) | Should -Be @()
        @($r3.Actions) | Should -Be @()
    }

    It 'keyup after recording produces a single stop' {
        $state = New-FreshAgentPttMachineState
        $state.KeyWasDown = $true
        $state.Holding = $true
        $r = Update-FreshAgentPttMachine -State $state -KeyDown $false -Recording $true -Transcribing $false
        @($r.Actions) | Should -Be @('stop')
    }

    It 'ignores start while transcribing' {
        $state = New-FreshAgentPttMachineState
        $r = Update-FreshAgentPttMachine -State $state -KeyDown $true -Recording $false -Transcribing $true
        @($r.Actions) | Should -Be @()
    }

    It 'requires release after recording ends while key held' {
        $state = New-FreshAgentPttMachineState
        $state.Holding = $true
        $state = Sync-FreshAgentPttMachineAfterRecording -State $state -KeyDown $true -Recording $false
        $state.RequireRelease | Should -Be $true
        $r = Update-FreshAgentPttMachine -State $state -KeyDown $true -Recording $false -Transcribing $false
        @($r.Actions) | Should -Be @()
        $r2 = Update-FreshAgentPttMachine -State $r.State -KeyDown $false -Recording $false -Transcribing $false
        @($r2.Actions) | Should -Be @()
        $r2.State.RequireRelease | Should -Be $false
    }
}
