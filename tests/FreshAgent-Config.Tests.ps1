#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'FreshAgent config sync list' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        . (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
    }

    It 'Expand config paths from registry' {
        $raw = Get-FreshAgentRepoRawRoot -RepoRef 'main'
        $list = Get-FreshAgentRepoConfigSyncList -RepoRawRoot $raw -FreshAppData (Join-Path $env:TEMP 'FreshAgent-SyncList-Test')
        $list.Count | Should -BeGreaterThan 6
        ($list | Where-Object { $_ -match 'check_system_health.json' }) | Should -Not -BeNullOrEmpty
    }
}
