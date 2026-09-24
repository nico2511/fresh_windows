#Requires -Version 5.1
<#
.SYNOPSIS
  Test agent sur UNE seule version: clone Git -> AppData isole -> tests WinForms.
.PARAMETER RepoRoot
  Racine du depot (defaut: parent de scripts).
.PARAMETER FreshAppData
  Cible (defaut: %LOCALAPPDATA%\FreshWindows). Utiliser un dossier dedie pour ne pas melanger.
.EXAMPLE
  # Test sans toucher votre AppData habituelle:
  powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-IsolatedAgentTest.ps1 `
    -FreshAppData "$env:TEMP\FreshWindows-TestOnly"
#>
param(
    [string]$RepoRoot = '',
    [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows')
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$tests = Join-Path $RepoRoot 'tests'

Write-Host "=== Arret agents existants ===" -ForegroundColor Cyan
$stop = Join-Path $PSScriptRoot 'Stop-FreshWatchAgent.ps1'
if (Test-Path -LiteralPath $stop) {
    & $stop
}

Write-Host "=== Dev-Sync (une source: $RepoRoot -> $FreshAppData) ===" -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Dev-SyncFreshAgentFromRepo.ps1') -RepoRoot $RepoRoot -FreshAppData $FreshAppData

Write-Host "=== Test contenu sync ===" -ForegroundColor Cyan
& (Join-Path $tests 'Test-IsolatedAppDataSync.ps1') -RepoRoot $RepoRoot -FreshAppData $FreshAppData

Write-Host "=== Test dispatch dashboard (STA) ===" -ForegroundColor Cyan
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $self = $PSCommandPath
    $arg = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`"", '-RepoRoot', "`"$RepoRoot`"", '-FreshAppData', "`"$FreshAppData`"")
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $ps @arg
    exit $LASTEXITCODE
}

$env:LOCALAPPDATA = Split-Path -Parent $FreshAppData
$script:WatchAgentSessionState = $ExecutionContext.SessionState
& (Join-Path $tests 'Test-DashboardClickClosure.ps1')

Write-Host ""
Write-Host 'OK tests isoles - lancer l agent:' -ForegroundColor Green
$startCmd = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
Write-Host "  $startCmd" -ForegroundColor Cyan
