#Requires -Version 5.1
<#
.SYNOPSIS
  Arrete toutes les instances Fresh Agent (systray / Launch-GameModeWatch).
.DESCRIPTION
  Cible les processus PowerShell dont la ligne de commande contient
  GameMode-WatchAgent ou Launch-GameModeWatch. N'attaque pas l'instance
  qui execute ce script (sauf -IncludeSelf).
.PARAMETER IncludeSelf
  Inclure le PID courant (utile en test).
.PARAMETER Force
  Stop-Process -Force (defaut: oui).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Stop-FreshWatchAgent.ps1
#>
param(
    [switch]$IncludeSelf,
    [switch]$Force = $true
)

$ErrorActionPreference = 'Continue'
$self = $PID
$pattern = 'GameMode-WatchAgent|Launch-GameModeWatch|Start-WatchAgent\.cmd'

function Get-FreshWatchAgentProcesses {
    $out = @()
    try {
        Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object {
                $_.Name -match '^(?i)(powershell|pwsh)(\.exe)?$' -and
                $_.CommandLine -and
                $_.CommandLine -match $pattern
            } | ForEach-Object { $out += $_ }
    }
    catch {
        Write-Warning ("CIM indisponible: {0}" -f $_.Exception.Message)
    }
    return $out
}

$peers = @(Get-FreshWatchAgentProcesses)
if (-not $IncludeSelf) {
    $peers = @($peers | Where-Object { $_.ProcessId -ne $self })
}

if ($peers.Count -eq 0) {
    Write-Host 'Aucun processus Fresh Agent trouve.' -ForegroundColor DarkGray
    exit 0
}

Write-Host ("Arret de {0} processus Fresh Agent..." -f $peers.Count) -ForegroundColor Yellow
foreach ($p in $peers) {
    $procId = [int]$p.ProcessId
    $line = [string]$p.CommandLine
    if ($line.Length -gt 120) { $line = $line.Substring(0, 117) + '...' }
    Write-Host ("  PID {0}: {1}" -f $procId, $line) -ForegroundColor DarkGray
    try {
        if ($Force) {
            Stop-Process -Id $procId -Force -ErrorAction Stop
        }
        else {
            Stop-Process -Id $procId -ErrorAction Stop
        }
        Write-Host ("  -> arrete PID {0}" -f $procId) -ForegroundColor Green
    }
    catch {
        Write-Warning ("  -> echec PID {0}: {1}" -f $procId, $_.Exception.Message)
    }
}

Start-Sleep -Milliseconds 400
$left = @(Get-FreshWatchAgentProcesses | Where-Object { $_.ProcessId -ne $self -or $IncludeSelf })
if ($left.Count -gt 0) {
    Write-Warning ("{0} processus encore actifs apres arret." -f $left.Count)
    exit 2
}

Write-Host 'Fresh Agent arrete.' -ForegroundColor Green
exit 0
