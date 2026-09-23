#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-SkillsEngine.ps1')
. (Join-Path $root 'scripts\ai\FreshAgent-OllamaBridge.ps1')

Describe 'FreshAgent Ollama bridge' {
    It 'Parse JSON skill request from text' {
        $r = Get-FreshAgentSkillRequestFromText -Text '{"skill":"youtube_search","parameters":{"query":"lofi"}}'
        $r.SkillId | Should -Be 'youtube_search'
        $r.Parameters.query | Should -Be 'lofi'
    }
    It 'Build tool schema from registry' {
        $tools = Get-FreshAgentAiToolSchema -RepoRef 'main' -FreshAppData (Join-Path $env:TEMP 'FreshAgent-Test-Missing')
        $tools.Count | Should -BeGreaterThan 0
        ($tools | Where-Object { $_.function.name -eq 'youtube_search' }) | Should -Not -BeNullOrEmpty
    }
}
