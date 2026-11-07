#Requires -Version 5.1
# Desinstallation Fresh Windows (agent, taches, cache local, raccourcis Fresh)
# PowerShell ADMIN. Simulation : -DryRun
# Suppression reelle : -Confirmed obligatoire (menu ou CLI).
# Reinstall : -ReinstallAfter + launcher officiel main apres nettoyage reussi.
param(
    [switch]$DryRun,
    [switch]$ReinstallAfter,
    [switch]$Confirmed
)

$ErrorActionPreference = 'Continue'
$script:FreshUninstallSelfPid = $PID
$script:FreshUninstallRepoMainLauncher = 'https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1'
$freshUninstallProgramData = $env:ProgramData
if ([string]::IsNullOrWhiteSpace($freshUninstallProgramData)) {
    $freshUninstallProgramData = [System.IO.Path]::GetTempPath()
}
$script:FreshUninstallProgramDataDir = Join-Path $freshUninstallProgramData 'FreshWindows'

function Get-FreshUninstallLocalRoot {
    return (Join-Path $env:LOCALAPPDATA 'FreshWindows')
}

function Test-FreshUninstallPathUnderRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $full = [System.IO.Path]::GetFullPath($Path.TrimEnd('\', '/'))
        $rootFull = [System.IO.Path]::GetFullPath($Root.TrimEnd('\', '/'))
        if ($full.Length -lt $rootFull.Length) { return $false }
        return $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Test-FreshUninstallProcessImmune {
    param(
        [int]$ProcessId,
        [string]$CommandLine = ''
    )
    if ($ProcessId -eq $script:FreshUninstallSelfPid) { return $true }
    if ($CommandLine -match 'Uninstall-FreshWindows|Launch-AfterUninstall') { return $true }
    return $false
}

function Get-FreshUninstallTargetProcesses {
    param([Parameter(Mandatory)][string]$FreshRoot)
    $out = [System.Collections.ArrayList]@()
    $freshEsc = [regex]::Escape($FreshRoot)
    $agentPattern = 'GameMode-WatchAgent|Launch-GameModeWatch|Start-WatchAgent\.cmd'
    $hostPattern = 'FreshAgent-VoiceHost'
    $launchPattern = 'Launch-FreshWindows\.ps1|Launch-GameModeKill\.ps1'

    foreach ($n in @('powershell', 'pwsh')) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            if (Test-FreshUninstallProcessImmune -ProcessId $p.Id) { continue }
            $cmd = $null
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction SilentlyContinue).CommandLine
            }
            catch { }
            if (-not $cmd) { continue }
            if ($cmd -notmatch $freshEsc) { continue }
            if ($cmd -match $agentPattern -or $cmd -match $hostPattern -or $cmd -match $launchPattern) {
                [void]$out.Add([pscustomobject]@{ ProcessId = $p.Id; Name = $p.ProcessName; CommandLine = $cmd })
            }
        }
    }

    $binMarker = [regex]::Escape((Join-Path $FreshRoot 'bin'))
    foreach ($p in @(Get-Process -Name 'voice_worker' -ErrorAction SilentlyContinue)) {
        if (Test-FreshUninstallProcessImmune -ProcessId $p.Id) { continue }
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
        [void]$out.Add([pscustomobject]@{ ProcessId = $p.Id; Name = $p.ProcessName; CommandLine = $path })
    }
    return @($out | Sort-Object ProcessId -Unique)
}

function Invoke-FreshUninstallDoStep {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($DryRun) {
        Write-Host "[SIMULATION] $Label" -ForegroundColor Yellow
        return $true
    }
    Write-Host "[OK] $Label" -ForegroundColor Green
    try {
        & $Action
        return $true
    }
    catch {
        Write-Host "[ECHEC] $Label : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-FreshUninstallDesktopShortcuts {
    $desktopUser = [Environment]::GetFolderPath('Desktop')
    $desktopPublic = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $names = @('Fresh Windows.lnk', 'FreshWindows.lnk', 'Mode Jeu.lnk')
    $paths = [System.Collections.ArrayList]@()
    foreach ($root in @($desktopUser, $desktopPublic)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        foreach ($name in $names) {
            $p = Join-Path $root $name
            if (Test-Path -LiteralPath $p) { [void]$paths.Add($p) }
        }
    }
    return @($paths)
}

function Get-FreshUninstallTempTestDirs {
    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) { return @() }
    $resolvedTemp = $null
    try { $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot) } catch { return @() }
    $dirs = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $resolvedTemp -Directory -ErrorAction SilentlyContinue)) {
        if ($d.Name -notmatch '^fw-test') { continue }
        if (-not (Test-FreshUninstallPathUnderRoot -Path $d.FullName -Root $resolvedTemp)) { continue }
        $dirs += $d.FullName
    }
    return $dirs
}

function Get-FreshUninstallLeftovers {
    param([Parameter(Mandatory)][string]$FreshRoot)
    $left = [System.Collections.ArrayList]@()
    if (Test-Path -LiteralPath $FreshRoot) { [void]$left.Add("Dossier encore present : $FreshRoot") }
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -like 'FreshWindows-*' } |
        ForEach-Object { [void]$left.Add("Tache encore presente : $($_.TaskName)") }
    foreach ($p in @(Get-FreshUninstallTargetProcesses -FreshRoot $FreshRoot)) {
        [void]$left.Add("Processus encore actif : $($p.ProcessId) $($p.Name)")
    }
    return @($left)
}

function Write-FreshUninstallReinstallStub {
    New-Item -ItemType Directory -Path $script:FreshUninstallProgramDataDir -Force | Out-Null
    $stubPath = Join-Path $script:FreshUninstallProgramDataDir 'Launch-AfterUninstall.ps1'
    $mainUrl = $script:FreshUninstallRepoMainLauncher
    $content = @"
#Requires -RunAsAdministrator
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$fresh = Join-Path `$env:LOCALAPPDATA 'FreshWindows'
`$deadline = (Get-Date).AddMinutes(8)
while ((Test-Path -LiteralPath `$fresh) -and (Get-Date) -lt `$deadline) {
    Start-Sleep -Seconds 2
}
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch {}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
`$env:FRESH_WIN_REF = 'main'
try {
    irm '$mainUrl' | iex
    exit 0
}
catch {
    Write-Host "Echec relance Fresh Windows (reseau ou acces) : `$(`$_.Exception.Message)" -ForegroundColor Red
    Write-Host "Relance manuelle : powershell -NoProfile -ExecutionPolicy Bypass -Command \"irm '$mainUrl' | iex\"" -ForegroundColor Yellow
    exit 3
}
"@
    Set-Content -LiteralPath $stubPath -Value $content -Encoding UTF8
    try { Unblock-File -LiteralPath $stubPath -ErrorAction SilentlyContinue } catch { }
    return $stubPath
}

function Start-FreshUninstallReinstallLauncher {
    param([Parameter(Mandatory)][string]$StubPath)
    if (-not (Test-Path -LiteralPath $StubPath)) {
        Write-Host "Stub relance introuvable : $StubPath" -ForegroundColor Red
        return $false
    }
    try {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$StubPath`"" `
            -WindowStyle Normal
        Write-Host "Relance Fresh Windows planifiee (nouvelle fenetre admin)." -ForegroundColor Cyan
        return $true
    }
    catch {
        Write-Host "Impossible de demarrer la relance : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Commande manuelle : powershell -NoProfile -ExecutionPolicy Bypass -Command `"irm $($script:FreshUninstallRepoMainLauncher) | iex`"" -ForegroundColor Yellow
        return $false
    }
}

function Invoke-FreshWindowsUninstall {
    if (-not $DryRun -and -not $Confirmed) {
        Write-Host "Annule : confirmation explicite requise (-Confirmed) ou utiliser -DryRun." -ForegroundColor Yellow
        return 2
    }

$fresh = Get-FreshUninstallLocalRoot
$freshExpected = Join-Path $env:LOCALAPPDATA 'FreshWindows'
try {
    $freshCanonical = [System.IO.Path]::GetFullPath($freshExpected)
}
catch {
    Write-Host "Chemin Fresh Windows invalide." -ForegroundColor Red
    return 1
}

Write-Host "`n=== Desinstallation Fresh Windows ===" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "Mode simulation : aucune modification." -ForegroundColor Yellow
}
elseif ($ReinstallAfter) {
    Write-Host "Reinstall apres nettoyage : launcher main GitHub." -ForegroundColor DarkCyan
}

$knownTasks = @(
    'FreshWindows-SyncLocalScripts',
    'FreshWindows-WatchAgent',
    'FreshWindows-WingetUpgrade',
    'FreshWindows-WinUtilReapply'
)

$targets = @(Get-FreshUninstallTargetProcesses -FreshRoot $freshCanonical)
foreach ($p in $targets) {
    $null = Invoke-FreshUninstallDoStep -Label "Arret du processus $($p.ProcessId) ($($p.Name))" -Action {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -like 'FreshWindows-*' -or ($knownTasks -contains $_.TaskName) } |
    ForEach-Object {
        $t = $_
        $null = Invoke-FreshUninstallDoStep -Label "Suppression de la tache $($t.TaskPath)$($t.TaskName)" -Action {
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
        }
    }

foreach ($lnk in @(Get-FreshUninstallDesktopShortcuts)) {
    $null = Invoke-FreshUninstallDoStep -Label "Suppression du raccourci $lnk" -Action {
        Remove-Item -LiteralPath $lnk -Force -ErrorAction Stop
    }
}

if (Test-Path -LiteralPath $freshCanonical) {
    if (-not (Test-FreshUninstallPathUnderRoot -Path $freshCanonical -Root (Join-Path $env:LOCALAPPDATA ''))) {
        Write-Host "Refus : chemin Fresh Windows hors AppData local attendu." -ForegroundColor Red
        return 1
    }
    if (-not $DryRun) { Start-Sleep -Seconds 2 }
    $null = Invoke-FreshUninstallDoStep -Label "Suppression du dossier $freshCanonical" -Action {
        Remove-Item -LiteralPath $freshCanonical -Recurse -Force -ErrorAction Stop
    }
}

foreach ($d in @(Get-FreshUninstallTempTestDirs)) {
    $null = Invoke-FreshUninstallDoStep -Label "Suppression du dossier temporaire $d" -Action {
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop
    }
}

Write-Host "`n--- Verification ---"
$left = @(Get-FreshUninstallLeftovers -FreshRoot $freshCanonical)
$reinstallOk = $false

if ($DryRun) {
    Write-Host "Simulation terminee, rien n'a ete supprime." -ForegroundColor Yellow
    return 0
}

if ($left.Count -gt 0) {
    $left | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "Nettoyage incomplet : relance ou arret manuel requis." -ForegroundColor Red
    return 1
}

Write-Host "Fresh Windows est entierement supprime (cache local / agent / taches)." -ForegroundColor Green

if ($ReinstallAfter) {
    $stub = Write-FreshUninstallReinstallStub
    $reinstallOk = Start-FreshUninstallReinstallLauncher -StubPath $stub
    if (-not $reinstallOk) { return 3 }
}

return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = Invoke-FreshWindowsUninstall
    exit $exitCode
}
