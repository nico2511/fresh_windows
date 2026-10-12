#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'FreshAgent Ollama bridge' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        . (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
        . (Join-Path $root 'scripts\lib\FreshAgent-SkillsEngine.ps1')
        . (Join-Path $root 'scripts\ai\FreshAgent-OllamaBridge.ps1')
    }

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
