#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Windows STT voice routing' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        . (Join-Path $root 'scripts\ai\Windows-Stt.ps1')
    }

    It 'Map session jeu' {
        $m = Get-FreshAgentVoiceDirectSkill -Transcript 'lance session jeu'
        $m.SkillId | Should -Be 'game_session'
    }
    It 'Map youtube search' {
        $m = Get-FreshAgentVoiceDirectSkill -Transcript 'mets du lofi sur youtube'
        $m.SkillId | Should -Be 'youtube_search'
        $m.Parameters.query | Should -Not -BeNullOrEmpty
    }
}
