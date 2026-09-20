#Requires -Version 5.1
<#
.SYNOPSIS
  Ferme les processus " mode jeu " (liste générique GitHub). Pas besoin d'admin pour tes propres apps.
.EXAMPLE
  irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/scripts/Invoke-GameModeKill.ps1 | iex
#>
$ErrorActionPreference = 'Stop'

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$commonPath = $null
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $commonPath = Join-Path $PSScriptRoot 'GameMode-Common.ps1'
}
if ($commonPath -and (Test-Path -LiteralPath $commonPath)) {
    . $commonPath
}
else {
    $ref = if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }
    $commonUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$ref/scripts/GameMode-Common.ps1"
    $tmp = Join-Path $env:TEMP "GameMode-Common.ps1"
    Invoke-WebRequest -Uri $commonUrl -OutFile $tmp -UseBasicParsing
    . $tmp
}

Write-Host "`n=== MODE JEU - fermeture processus lourds ===" -ForegroundColor Red
Write-Host "(Liste generique : dev / IA / sync / Bitwarden - Discord/Legcord proteges)" -ForegroundColor DarkGray
Write-Host "Launchers : familles (EA/Steam/...) - session active jamais tuee." -ForegroundColor DarkGray

Ensure-UltimatePerformanceActive | Out-Null

$cfg = Get-GameModeKillConfig
$result = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames
$idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames -LauncherFamilies $cfg.GamingLauncherFamilies

if ($result.Killed.Count -gt 0) {
    Write-Host "`nFermes ($($result.Killed.Count)) :" -ForegroundColor Green
    $result.Killed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
}
else {
    Write-Host "`nAucun process de la liste n'etait ouvert." -ForegroundColor Yellow
}
if ($result.Skipped.Count -gt 0) {
    Write-Host "Ignores :" -ForegroundColor DarkYellow
    $result.Skipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
}
if ($idle.Notes) {
    foreach ($n in $idle.Notes) {
        Write-Host "  $n" -ForegroundColor DarkCyan
    }
}
if ($idle.Killed.Count -gt 0) {
    Write-Host "`nLaunchers idle fermes ($($idle.Killed.Count)) :" -ForegroundColor Green
    $idle.Killed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
}
if ($idle.Kept.Count -gt 0) {
    Write-Host "Launchers conserves :" -ForegroundColor DarkCyan
    $idle.Kept | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
}

if ($env:FRESH_WIN_NO_PAUSE -ne '1') {
    Read-Host "`nEntree pour fermer"
}
