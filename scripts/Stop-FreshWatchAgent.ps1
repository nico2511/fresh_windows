#Requires -Version 5.1
<#
.SYNOPSIS
  Arrete toutes les instances Fresh Agent (systray / Launch-GameModeWatch).
.DESCRIPTION
  Cible les processus PowerShell dont la ligne de commande contient
  GameMode-WatchAgent ou Launch-GameModeWatch. N'attaque pas l'instance
  qui execute ce script (sauf -IncludeSelf).

  Important: ne jamais enumerer TOUS les Win32_Process (Get-CimInstance sans filtre)
  — ca peut bloquer des minutes sur certaines machines.
#>
param(
    [switch]$IncludeSelf,
    [switch]$Force = $true,
    [string]$FreshAppData = ''
)

$ErrorActionPreference = 'Continue'
$self = $PID
$pattern = 'GameMode-WatchAgent|Launch-GameModeWatch|Start-WatchAgent\.cmd'

function Get-FreshWatchAgentProcesses {
    $out = [System.Collections.ArrayList]@()
    $names = @('powershell', 'pwsh')
    foreach ($n in $names) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            if (-not $IncludeSelf -and $p.Id -eq $self) { continue }
            $cmd = $null
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction SilentlyContinue).CommandLine
            }
            catch { }
            if (-not $cmd) { continue }
            if ($cmd -notmatch $pattern) { continue }
            if ($FreshAppData -and ($cmd -notmatch [regex]::Escape($FreshAppData))) { continue }
            [void]$out.Add([pscustomobject]@{
                    ProcessId   = $p.Id
                    CommandLine = $cmd
                })
        }
    }
    return @($out)
}

function Stop-FreshAgentScopedHelpers {
    param([string]$AppDataRoot)
    if ([string]::IsNullOrWhiteSpace($AppDataRoot)) { return }
    $binMarker = [regex]::Escape((Join-Path $AppDataRoot 'bin'))
    $hostMarker = 'FreshAgent-VoiceHost'
    $appEsc = [regex]::Escape($AppDataRoot)

    # VoiceHost PowerShell (profil AppData uniquement)
    foreach ($n in @('powershell', 'pwsh')) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            if ($p.Id -eq $self) { continue }
            $cmd = $null
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction SilentlyContinue).CommandLine
            }
            catch { }
            if (-not $cmd) { continue }
            if ($cmd -notmatch $hostMarker) { continue }
            if ($cmd -notmatch $appEsc) { continue }
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                Write-Host ("  -> VoiceHost arrete PID {0}" -f $p.Id) -ForegroundColor Green
            }
            catch {
                Write-Warning ("  -> echec VoiceHost PID {0}: {1}" -f $p.Id, $_.Exception.Message)
            }
        }
    }

    # voice_worker.exe uniquement sous FreshWindows*\bin (jamais Programs\CyberScribe)
    foreach ($p in @(Get-Process -Name 'voice_worker' -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $p.Path } catch { }
        if (-not $path) {
            try {
                $path = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction SilentlyContinue).ExecutablePath
            }
            catch { }
        }
        if (-not $path) { continue }
        if ($path -notmatch $binMarker) { continue }
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Host ("  -> voice_worker arrete PID {0}" -f $p.Id) -ForegroundColor Green
        }
        catch {
            Write-Warning ("  -> echec voice_worker PID {0}: {1}" -f $p.Id, $_.Exception.Message)
        }
    }
}

$peers = @(Get-FreshWatchAgentProcesses)
Write-Host ("Arret Fresh Agent (profil={0})..." -f $(if ($FreshAppData) { $FreshAppData } else { 'tous' })) -ForegroundColor Yellow
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

if ($FreshAppData) {
    Stop-FreshAgentScopedHelpers -AppDataRoot $FreshAppData
}
else {
    foreach ($root in @(
            (Join-Path $env:LOCALAPPDATA 'FreshWindows'),
            (Join-Path $env:LOCALAPPDATA 'FreshWindows-Dev')
        )) {
        if (Test-Path -LiteralPath $root) {
            Stop-FreshAgentScopedHelpers -AppDataRoot $root
        }
    }
}

Start-Sleep -Milliseconds 500
$left = @(Get-FreshWatchAgentProcesses)
if ($left.Count -gt 0) {
    Write-Warning ("{0} processus agent encore actifs apres arret." -f $left.Count)
    exit 2
}

Write-Host 'Fresh Agent arrete (process propres).' -ForegroundColor Green
exit 0
