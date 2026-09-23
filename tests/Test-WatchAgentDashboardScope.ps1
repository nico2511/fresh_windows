#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
$script:WatchAgentSessionState = $ExecutionContext.SessionState
$configPath = Join-Path $PSScriptRoot '..\scripts\lib\FreshAgent-Config.ps1'
. (Resolve-Path -LiteralPath $configPath)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction SilentlyContinue
$ok = Import-FreshAgentModule -RelativePath 'lib/FreshAgent-Dashboard.ps1' -FreshAppData $FreshAppData
if (-not $ok) { Write-Error 'Import-FreshAgentModule dashboard failed' }
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    Write-Error 'Show-FreshAgentDashboard absent apres Import-FreshAgentModule'
}
Write-Host 'OK dashboard command visible in script scope'
