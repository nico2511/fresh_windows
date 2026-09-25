#Requires -Version 5.1
<#
.SYNOPSIS
  Lance Fresh Agent sur le profil AppData isole FreshWindows-Dev.
#>
param(
    [string]$RepoRoot = '',
    [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows-Dev')
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}

$sync = Join-Path $PSScriptRoot 'Dev-SyncFreshAgentFromRepo.ps1'
& $sync -RepoRoot $RepoRoot -FreshAppData $FreshAppData

$env:FRESH_WIN_APPDATA = $FreshAppData
$stop = Join-Path $PSScriptRoot 'Stop-FreshAgentDev.ps1'
& $stop -FreshAppData $FreshAppData

$agent = Join-Path $FreshAppData 'GameMode-WatchAgent.ps1'
if (-not (Test-Path -LiteralPath $agent)) {
    throw "GameMode-WatchAgent.ps1 manquant: $agent"
}
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
Write-Host "Demarrage agent Dev: $FreshAppData" -ForegroundColor Cyan
Start-Process -FilePath $psExe -ArgumentList @(
    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
    '-File', $agent
) -WorkingDirectory $FreshAppData
