#Requires -Version 5.1
<#
.SYNOPSIS
  Ferme les processus « mode jeu » (liste générique GitHub). Pas besoin d'admin pour tes propres apps.
.EXAMPLE
  irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/scripts/Invoke-GameModeKill.ps1 | iex
#>
$ErrorActionPreference = 'Stop'

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$commonPath = Join-Path $PSScriptRoot 'GameMode-Common.ps1'
if (Test-Path -LiteralPath $commonPath) {
    . $commonPath
}
else {
    $ref = if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }
    $commonUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$ref/scripts/GameMode-Common.ps1"
    $tmp = Join-Path $env:TEMP "GameMode-Common.ps1"
    Invoke-WebRequest -Uri $commonUrl -OutFile $tmp -UseBasicParsing
    . $tmp
}

Write-Host "`n=== MODE JEU — fermeture processus lourds ===" -ForegroundColor Red
Write-Host "(Liste générique : dev / IA / 3D / vidéo / sync — pas comm ni gaming)" -ForegroundColor DarkGray

$cfg = Get-GameModeKillConfig
$result = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames

if ($result.Killed.Count -gt 0) {
    Write-Host "`nFermés ($($result.Killed.Count)) :" -ForegroundColor Green
    $result.Killed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
}
else {
    Write-Host "`nAucun process de la liste n'était ouvert." -ForegroundColor Yellow
}
if ($result.Skipped.Count -gt 0) {
    Write-Host "Ignorés :" -ForegroundColor DarkYellow
    $result.Skipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
}

if ($env:FRESH_WIN_NO_PAUSE -ne '1') {
    Read-Host "`nEntrée pour fermer"
}
