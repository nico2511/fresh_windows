#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\ai\Windows-Stt.ps1')

Describe 'Windows STT voice routing' {
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
