#Requires -Version 5.1
<#
.SYNOPSIS
  Smoke test: sync + start FreshWindows-Dev, verifie mutex / AppData / icone dans le log.
#>
param(
    [string]$RepoRoot = '',
    [int]$WaitSec = 10
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    if (-not (Test-Path (Join-Path $RepoRoot 'scripts\Start-FreshAgentDev.ps1'))) {
        $RepoRoot = Split-Path $PSScriptRoot -Parent
    }
}
$scripts = Join-Path $RepoRoot 'scripts'
$fresh = Join-Path $env:LOCALAPPDATA 'FreshWindows-Dev'
$log = Join-Path $fresh 'watch-agent.log'

& (Join-Path $scripts 'Stop-FreshAgentDev.ps1') -FreshAppData $fresh
if (Test-Path $log) { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }

& (Join-Path $scripts 'Start-FreshAgentDev.ps1') -RepoRoot $RepoRoot -FreshAppData $fresh
Start-Sleep -Seconds $WaitSec

if (-not (Test-Path -LiteralPath $log)) {
    Write-Host 'FAIL: pas de watch-agent.log' -ForegroundColor Red
    exit 1
}

$tail = Get-Content -LiteralPath $log -Raw -Encoding UTF8
$checks = @(
    @{ Name = 'Mutex acquis'; Ok = ($tail -match 'Mutex acquis') },
    @{ Name = 'AppData Dev'; Ok = ($tail -match 'FreshWindows-Dev') },
    @{ Name = 'NotifyIcon'; Ok = ($tail -match 'NotifyIcon visible') },
    @{ Name = 'Pas Split-Path null'; Ok = ($tail -notmatch 'ParameterArgumentValidationErrorNullNotAllowed') },
    @{ Name = 'OllamaBridge charge'; Ok = ($tail -match 'Module boot: ai/FreshAgent-OllamaBridge' -and $tail -notmatch 'Module Fresh Agent absent: ai/FreshAgent-OllamaBridge') },
    @{ Name = 'Boot finalise'; Ok = ($tail -match 'voice auto-start disabled|Module boot: finalisation') }
)

$bad = 0
foreach ($c in $checks) {
    if ($c.Ok) { Write-Host ("OK    {0}" -f $c.Name) -ForegroundColor Green }
    else { Write-Host ("FAIL  {0}" -f $c.Name) -ForegroundColor Red; $bad++ }
}

Write-Host ''
Write-Host '--- dernieres lignes log ---' -ForegroundColor DarkGray
Get-Content -LiteralPath $log -Tail 12
exit $bad
