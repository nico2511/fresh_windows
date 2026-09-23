#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')

Describe 'FreshAgent config sync list' {
    It 'Expand config paths from registry' {
        $raw = Get-FreshAgentRepoRawRoot -RepoRef 'main'
        $list = Get-FreshAgentRepoConfigSyncList -RepoRawRoot $raw -FreshAppData (Join-Path $env:TEMP 'FreshAgent-SyncList-Test')
        $list.Count | Should -BeGreaterThan 6
        ($list | Where-Object { $_ -match 'check_system_health.json' }) | Should -Not -BeNullOrEmpty
    }
}
