#Requires -Version 5.1
<#
.SYNOPSIS
  Harness NON DESTRUCTIF pour Windows PowerShell 5.1 (tests sandboxes / mocks).
.DESCRIPTION
  Mode sur par defaut : DryRun + SandboxLocalAppDataRoot sous %TEMP%.
  Aucun arret de processus, aucune tache reelle, aucune elevation requise pour -DryRun.
  Fichiers necessaires (sans clone) depuis la branche main :
    - scripts/lib/FreshWindows-Uninstall.ps1
    - tests/Invoke-UninstallSafeHarness.ps1
  Optionnel (tests menu staging uniquement si present localement) :
    - scripts/Uninstall-FreshWindows.ps1
    - scripts/lib/Launcher-Core.ps1
.EXAMPLE
  pwsh -NoProfile -File .\tests\Invoke-UninstallSafeHarness.ps1
  powershell -NoProfile -File .\tests\Invoke-UninstallSafeHarness.ps1
#>
param(
    [switch]$StrictOui,
    [switch]$RunPesterSelf
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:TEMP)) { $env:TEMP = [System.IO.Path]::GetTempPath() }
$root = Split-Path $PSCommandPath -Parent | Split-Path -Parent
$lib = Join-Path $root 'scripts/lib/FreshWindows-Uninstall.ps1'
if (-not (Test-Path -LiteralPath $lib)) {
    Write-Host "Missing $lib" -ForegroundColor Red
    exit 1
}

$sandbox = Join-Path $env:TEMP ("FreshWindows-SafeHarness-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
$fresh = Join-Path $sandbox 'FreshWindows'
New-Item -ItemType Directory -Path $fresh -Force | Out-Null

Write-Host "Harness sandbox : $sandbox" -ForegroundColor Cyan
. $lib -DryRun -SandboxLocalAppDataRoot $sandbox -ImmuneProcessIds @($PID)
$code = Invoke-FreshWindowsUninstall
Write-Host "DryRun exit code : $code" -ForegroundColor $(if ($code -eq 0) { 'Green' } else { 'Red' })

if ($RunPesterSelf) {
    if (-not (Get-Module -ListAvailable Pester)) {
        Write-Host 'Pester absent : installer 5.6.1' -ForegroundColor Yellow
    }
    else {
        Import-Module Pester -RequiredVersion 5.6.1 -Force -ErrorAction SilentlyContinue
        $cfg = New-PesterConfiguration
        $cfg.Run.Path = Join-Path (Split-Path $PSCommandPath -Parent) 'Uninstall-FreshWindows.Tests.ps1'
        $r = Invoke-Pester -Configuration $cfg -PassThru
        if ($r.FailedCount -gt 0) { exit 1 }
    }
}

Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
if ($code -ne 0) { exit $code }
Write-Host 'Harness OK (non destructif).' -ForegroundColor Green
exit 0
