#Requires -Version 5.1
<#
.SYNOPSIS
  Agent systray maintenance Fresh Windows (surveillance, mode jeu, sante).
.NOTES
  Prefs: %LOCALAPPDATA%\FreshWindows\watch-agent-user.json
  Lancer avec powershell.exe -STA (sinon l'icone n'apparait pas).
#>
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Continue'

$RepoRef = if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }
$RepoRawRoot = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef"
if ($env:FRESH_WIN_APPDATA -and -not [string]::IsNullOrWhiteSpace($env:FRESH_WIN_APPDATA)) {
    $FreshAppData = $env:FRESH_WIN_APPDATA.Trim()
}
elseif ($PSScriptRoot -and ((Split-Path $PSScriptRoot -Leaf) -match 'FreshWindows')) {
    $FreshAppData = $PSScriptRoot
}
else {
    $FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
}
$script:RepoRef = $RepoRef
$script:FreshAppData = $FreshAppData
$script:RepoRawRoot = $RepoRawRoot
$UserSettingsPath = Join-Path $FreshAppData 'watch-agent-user.json'
$WatchConfigLocal = Join-Path $FreshAppData 'configs\game-mode-watch.json'
$WatchConfigUrl = "$RepoRawRoot/configs/game-mode-watch.json"
$WatchLog = Join-Path $FreshAppData 'watch-agent.log'
try { New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null } catch { }

function Write-WatchLog {
    param([string]$Message)
    try {
        $dir = Split-Path $WatchLog
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $WatchLog -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    catch { }
}

function Set-WatchScriptUtf8Bom {
    param([Parameter(Mandatory)][string]$Path)
    if (Get-Command Set-FreshScriptUtf8Bom -ErrorAction SilentlyContinue) {
        Set-FreshScriptUtf8Bom -Path $Path
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return }
        $needsBom = $false
        foreach ($b in $bytes) { if ($b -gt 127) { $needsBom = $true; break } }
        if (-not $needsBom) { return }
        $text = (New-Object System.Text.UTF8Encoding $false).GetString($bytes)
        [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding $true))
    }
    catch { }
}

function Register-WatchUiHandler {
    param([object]$Handler)
    if (-not $script:WatchUiHandlers) {
        $script:WatchUiHandlers = New-Object System.Collections.ArrayList
    }
    if ($null -ne $Handler) { [void]$script:WatchUiHandlers.Add($Handler) }
    return $Handler
}

function Add-WatchMenuClick {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.ToolStripItem]$MenuItem,
        [Parameter(Mandatory)][scriptblock]$Handler
    )
    $wrapped = {
        param($sender, $e)
        $label = 'menu'
        try { if ($sender -and $sender.Text) { $label = [string]$sender.Text } } catch { }
        Write-WatchLog ("UI click begin: {0}" -f $label)
        try {
            try { & $Handler $sender $e }
            catch { & $Handler }
        }
        catch {
            Write-WatchLog ("UI click error ({0}): {1}" -f $label, $_.Exception.ToString())
        }
        Write-WatchLog ("UI click end: {0}" -f $label)
    }.GetNewClosure()
    $MenuItem.Add_Click((Register-WatchUiHandler $wrapped))
}

function Reset-WatchAgentSystrayUi {
    if ($script:NotifyIcon) {
        try { $script:NotifyIcon.Visible = $false } catch { }
        try { $script:NotifyIcon.Dispose() } catch { }
        $script:NotifyIcon = $null
    }
    if ($script:HiddenForm) {
        try {
            if (-not $script:HiddenForm.IsDisposed) { $script:HiddenForm.Dispose() }
        }
        catch { }
        $script:HiddenForm = $null
    }
}

function Test-WatchAgentSystrayLive {
    try {
        if (-not $script:HiddenForm -or $script:HiddenForm.IsDisposed) { return $false }
        if (-not $script:NotifyIcon) { return $false }
        return $true
    }
    catch { return $false }
}

function Stop-WatchAgentMessageLoop {
    try {
        if ($script:HiddenForm) {
            try {
                if (-not $script:HiddenForm.IsDisposed) { $script:HiddenForm.Close() }
            }
            catch { }
        }
    }
    catch { }
}

function Request-WatchAgentShutdown {
    Write-WatchLog 'Arret agent (Exit)'
    $script:WatchAgentExitRequested = $true
    Stop-WatchAgentPollTimerIfRunning
    try {
        if ($script:NotifyIcon) {
            $script:NotifyIcon.Visible = $false
            $script:NotifyIcon.Dispose()
            $script:NotifyIcon = $null
        }
    }
    catch { }
    try { Exit-FreshWatchAgentSingleInstance } catch { }
    Stop-WatchAgentMessageLoop
    [Environment]::Exit(0)
}

Write-WatchLog 'WatchAgent start (maintenance)'
$script:WatchAgentSessionState = $ExecutionContext.SessionState

$selfScript = $PSCommandPath
if (-not $selfScript) { $selfScript = $MyInvocation.MyCommand.Path }
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$psArg = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$selfScript`""

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-WatchLog 'Relance en STA'
    Start-Process -FilePath $psExe -ArgumentList $psArg
    exit 0
}

function Get-FreshWatchAgentPeerProcesses {
    $self = $PID
    $out = @()
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessId -ne $self -and
                $_.Name -match '^(?i)(powershell|pwsh)(\.exe)?$' -and
                $_.CommandLine -and
                $_.CommandLine -match 'GameMode-WatchAgent|Launch-GameModeWatch'
            } | ForEach-Object { $out += $_ }
    }
    catch { }
    return $out
}

function Enter-FreshWatchAgentSingleInstance {
    $mutexName = 'Global\FreshWindowsWatchAgent'
    $script:WatchMutex = $null
    $acquired = $false
    try {
        $script:WatchMutex = New-Object System.Threading.Mutex($false, $mutexName)
        try { $acquired = $script:WatchMutex.WaitOne(0, $false) }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
            Write-WatchLog 'Mutex abandonne (crash precedent) — reprise'
        }
        if (-not $acquired) {
            $peers = @(Get-FreshWatchAgentPeerProcesses)
            if ($peers.Count -eq 0) {
                Write-WatchLog 'Mutex bloque sans processus agent — reset'
                try { $script:WatchMutex.Dispose() } catch { }
                $script:WatchMutex = $null
                $created = $false
                $script:WatchMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
                $acquired = $true
            }
            else {
                $pids = ($peers | ForEach-Object { [string]$_.ProcessId }) -join ','
                Write-WatchLog ("Autre instance active (PID {0}) — exit" -f $pids)
                exit 0
            }
        }
        if ($acquired) { Write-WatchLog ("Mutex acquis PID $PID") }
    }
    catch {
        Write-WatchLog ("Mutex: {0}" -f $_.Exception.Message)
    }
}

function Exit-FreshWatchAgentSingleInstance {
    try {
        if ($script:WatchMutex) {
            try { [void]$script:WatchMutex.ReleaseMutex() } catch { }
            try { $script:WatchMutex.Dispose() } catch { }
            $script:WatchMutex = $null
        }
    }
    catch { }
}

Enter-FreshWatchAgentSingleInstance
Write-WatchLog 'Post-mutex OK'

function Hide-WatchConsole {
    try {
        if (-not ('FreshWinNative' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FreshWinNative {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
        }
        $hwnd = [FreshWinNative]::GetConsoleWindow()
        if ($hwnd -and $hwnd -ne [IntPtr]::Zero) {
            [void][FreshWinNative]::ShowWindow($hwnd, 0)
        }
    }
    catch { }
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    try {
        [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
            [System.Windows.Forms.UnhandledExceptionMode]::CatchException)
        [System.Windows.Forms.Application]::add_ThreadException({
                param($sender, $e)
                try {
                    $detail = if ($e.Exception) { $e.Exception.ToString() } else { 'unknown' }
                    Write-WatchLog ('UI ThreadException: {0}' -f $detail)
                }
                catch { }
            })
    }
    catch {
        Write-WatchLog ("ThreadException hook: {0}" -f $_.Exception.Message)
    }
    Write-WatchLog 'WinForms charge'
}
catch {
    Write-WatchLog ("WinForms echec: {0}" -f $_.Exception.Message)
    throw
}

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch { }

Write-WatchLog ("AppData={0} Ref={1}" -f $script:FreshAppData, $script:RepoRef)

function Import-WatchLib {
    param([string]$RelativePath)
    if (-not $RelativePath) { return $false }
    $rel = $RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    $candidates = @(
        (Join-Path $script:FreshAppData $rel),
        (Join-Path $PSScriptRoot $rel)
    )
    foreach ($path in $candidates) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            Set-WatchScriptUtf8Bom -Path $path
            $raw = [System.IO.File]::ReadAllText($path)
            $raw = [regex]::Replace($raw, '(?m)^(\s*)#Requires[^\r\n]*', '${1}# requires stripped')
            $raw = [regex]::Replace($raw, '(?m)^(\s*)function\s+(?!script:)([A-Za-z_][\w-]*)', '${1}function script:${2}')
            Invoke-Expression $raw
            Write-WatchLog ("Lib chargee: {0}" -f $path)
            return $true
        }
        catch {
            Write-WatchLog ("Lib erreur {0}: {1}" -f $path, $_.Exception.Message)
        }
    }
    Write-WatchLog ("Lib absente: {0}" -f $RelativePath)
    return $false
}

Write-WatchLog 'Chargement GameMode-Common'
$commonPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'GameMode-Common.ps1' } else { $null }
if ($commonPath -and (Test-Path -LiteralPath $commonPath)) {
    try {
        Set-WatchScriptUtf8Bom -Path $commonPath
        . $commonPath
    }
    catch {
        Write-WatchLog ("GameMode-Common local: {0}" -f $_.Exception.Message)
    }
}
else {
    $commonUrl = "$RepoRawRoot/scripts/GameMode-Common.ps1"
    $tmp = Join-Path $env:TEMP 'GameMode-Common.ps1'
    try {
        Invoke-WebRequest -Uri $commonUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 25
        Set-WatchScriptUtf8Bom -Path $tmp
        . $tmp
    }
    catch {
        Write-WatchLog ("GameMode-Common download: {0}" -f $_.Exception.Message)
    }
}

foreach ($lib in @(
        'lib/FreshAgent-MaintenanceConfig.ps1',
        'lib/FreshAgent-Log.ps1',
        'lib/FreshAgent-GameSession.ps1',
        'lib/FreshAgent-Optimize.ps1',
        'lib/FreshAgent-Health.ps1'
    )) {
    Import-WatchLib -RelativePath $lib | Out-Null
}

if (Get-Command Get-FreshAgentAppDataRoot -ErrorAction SilentlyContinue) {
    $script:FreshAppData = Get-FreshAgentAppDataRoot
    $FreshAppData = $script:FreshAppData
    $WatchLog = Join-Path $FreshAppData 'watch-agent.log'
    $UserSettingsPath = Join-Path $FreshAppData 'watch-agent-user.json'
    $WatchConfigLocal = Join-Path $FreshAppData 'configs\game-mode-watch.json'
}

$script:MaintenanceLibsReady = $true

function Get-WatchUserSettings {
    $defaults = @{
        autoSuggestKill = $true
        monitorEnabled  = $true
    }
    if (-not (Test-Path -LiteralPath $UserSettingsPath)) { return $defaults }
    try {
        $u = Get-Content -LiteralPath $UserSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return @{
            autoSuggestKill = if ($null -ne $u.autoSuggestKill) { [bool]$u.autoSuggestKill } else { $true }
            monitorEnabled  = if ($null -ne $u.monitorEnabled) { [bool]$u.monitorEnabled } else { $true }
        }
    }
    catch { return $defaults }
}

function Set-WatchUserSettings {
    param($Settings)
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $Settings | ConvertTo-Json | Set-Content -LiteralPath $UserSettingsPath -Encoding UTF8
}

function Get-WatchRulesDefault {
    return @{
        pollIntervalSeconds             = 12
        cpuThresholdPercent             = 28
        cpuSustainedSeconds             = 150
        ramAlertMinMb                   = 6144
        ramAlertPercentOfSystem         = 18
        diskBusyThresholdPercent        = 92
        diskBusySustainedSeconds        = 120
        diskAlertOnlyWhenNotGaming      = $true
        cooldownBetweenSameAlertSeconds = 300
        gamingSessionHeuristic          = @{ minProtectProcessRamMb = 400 }
        ignoreSuggestProcesses          = @('explorer', 'dwm', 'RuntimeBroker')
        knownDiskHogs                   = @('SearchIndexer', 'MsMpEng')
    }
}

function Get-WatchRules {
    $defaults = Get-WatchRulesDefault
    if (Test-Path -LiteralPath $WatchConfigLocal) {
        try {
            $r = Get-Content -LiteralPath $WatchConfigLocal -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($r) {
                Write-WatchLog ("Watch rules: local {0}" -f $WatchConfigLocal)
                return $r
            }
        }
        catch {
            Write-WatchLog ("Watch rules local: {0}" -f $_.Exception.Message)
        }
    }
    try {
        $r = Invoke-RestMethod -Uri $WatchConfigUrl -UseBasicParsing -TimeoutSec 12
        if ($r) {
            Write-WatchLog 'Watch rules: GitHub'
            return $r
        }
    }
    catch {
        Write-WatchLog ("Get-WatchRules remote: {0}" -f $_.Exception.Message)
    }
    return $defaults
}

$script:CpuTrack = @{}
$script:DiskHighSince = $null
$script:LastAlerts = @{}
$script:PendingKill = @{}
$script:GameModeCfg = $null
$script:WatchRules = Get-WatchRulesDefault
$script:WatchRulesRemotePending = $true
$script:UserSettings = Get-WatchUserSettings
$script:TotalRamMb = 16384
try {
    $script:TotalRamMb = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1MB)
}
catch {
    Write-WatchLog ("RAM systeme: {0}" -f $_.Exception.Message)
}

function Test-GamingSessionActive {
    param($GameModeCfg, $Rules)
    if (-not $GameModeCfg) { return $false }
    $heur = $Rules.gamingSessionHeuristic
    $minRam = if ($heur.minProtectProcessRamMb) { [double]$heur.minProtectProcessRamMb } else { 400 }
    $heavyGameRamMb = 2048
    foreach ($name in @($GameModeCfg.GamingLauncherNames)) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            if (($p.WorkingSet64 / 1MB) -ge $minRam) { return $true }
        }
    }
    $protect = @($GameModeCfg.ProtectNames)
    foreach ($p in Get-Process) {
        try {
            if (Test-GameModeProtectedProcess -ProcessName $p.ProcessName -ProtectNames $protect) { continue }
            if (($p.WorkingSet64 / 1MB) -ge $heavyGameRamMb) { return $true }
        }
        catch { }
    }
    return $false
}

function Show-Balloon {
    param(
        [string]$Title,
        [string]$Text,
        [System.Windows.Forms.ToolTipIcon]$Icon = 'Info'
    )
    if ($script:NotifyIcon) {
        $script:NotifyIcon.BalloonTipTitle = $Title
        $script:NotifyIcon.BalloonTipText = $Text
        $script:NotifyIcon.BalloonTipIcon = $Icon
        $script:NotifyIcon.ShowBalloonTip(8000)
    }
}

function Test-WatchIgnoredProcess {
    param([string]$ProcessName)
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $false }
    $list = @($script:WatchRules.ignoreSuggestProcesses)
    foreach ($n in $list) {
        if ($ProcessName.Equals([string]$n, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-AlertCooldown {
    param([string]$Key, [int]$CooldownSec)
    if (-not $script:LastAlerts.ContainsKey($Key)) { return $true }
    return ((Get-Date) - $script:LastAlerts[$Key]).TotalSeconds -ge $CooldownSec
}

function Mark-Alert {
    param([string]$Key)
    $script:LastAlerts[$Key] = Get-Date
}

function Update-MaintenanceTrayStatus {
    if (-not $script:NotifyIcon) { return }
    $text = 'Fresh Maintenance'
    try {
        if (Get-Command Get-FreshAgentGameSessionState -ErrorAction SilentlyContinue) {
            if (Get-FreshAgentGameSessionState -FreshAppData $script:FreshAppData) {
                $text = 'Fresh Maintenance | Jeu'
            }
        }
    }
    catch { }
    if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
    $script:NotifyIcon.Text = $text
}

function Invoke-WatchTick {
    if ($script:WatchRulesRemotePending) {
        $script:WatchRulesRemotePending = $false
        $script:WatchRules = Get-WatchRules
        Sync-WatchAgentPollTimer
    }
    $script:UserSettings = Get-WatchUserSettings
    Update-MaintenanceTrayStatus

    if (Get-Command Invoke-FreshAgentWeeklyHealthReportIfDue -ErrorAction SilentlyContinue) {
        try {
            $wr = Invoke-FreshAgentWeeklyHealthReportIfDue -FreshAppData $script:FreshAppData
            if ($wr -and $wr.ok) {
                $msg = [string]$wr.message
                if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 197) + '...' }
                Show-Balloon -Title 'Rapport hebdo' -Text $msg -Icon Info
            }
        }
        catch {
            Write-WatchLog ("Weekly report tick: {0}" -f $_.Exception.Message)
        }
    }

    if ($script:MaintenanceLibsReady -and (Get-Command Get-FreshAgentHealthSnapshot -ErrorAction SilentlyContinue)) {
        $due = $true
        try {
            if ($script:FaHealthSampleAt -and ((Get-Date) - [datetime]$script:FaHealthSampleAt).TotalMinutes -lt 5) {
                $due = $false
            }
        }
        catch { }
        if ($due) {
            try {
                $snap = Get-FreshAgentHealthSnapshot -FreshAppData $script:FreshAppData
                Add-FreshAgentHealthHistory -Snapshot $snap -FreshAppData $script:FreshAppData
                $script:FaHealthSampleAt = Get-Date
            }
            catch { }
        }
    }

    if (-not $script:UserSettings.monitorEnabled) { return }

    if (-not $script:GameModeCfg) {
        try { $script:GameModeCfg = Get-GameModeKillConfig } catch { return }
    }

    $rules = $script:WatchRules
    $protect = $script:GameModeCfg.ProtectNames
    $poll = [math]::Max(5, [int]$rules.pollIntervalSeconds)
    $cpuThr = [double]$rules.cpuThresholdPercent
    $cpuSec = [double]$rules.cpuSustainedSeconds
    $cooldown = [int]$rules.cooldownBetweenSameAlertSeconds
    $cores = [int]$env:NUMBER_OF_PROCESSORS
    if ($cores -lt 1) { $cores = 1 }

    $now = Get-Date
    $gaming = Test-GamingSessionActive -GameModeCfg $script:GameModeCfg -Rules $rules

    foreach ($p in Get-Process) {
        try {
            if ($p.Id -eq $PID) { continue }
            $name = $p.ProcessName
            if (Test-GameModeProtectedProcess -ProcessName $name -ProtectNames $protect) { continue }
            if (Test-WatchIgnoredProcess -ProcessName $name) { continue }

            $id = $p.Id
            $cpuTime = $p.CPU
            if (-not $script:CpuTrack.ContainsKey($id)) {
                $script:CpuTrack[$id] = @{ CpuTime = $cpuTime; At = $now; HighSince = $null }
                continue
            }

            $prev = $script:CpuTrack[$id]
            $wall = ($now - $prev.At).TotalSeconds
            if ($wall -lt ($poll * 0.5)) { continue }

            $cpuDelta = $cpuTime - $prev.CpuTime
            $pct = if ($wall -gt 0) { ($cpuDelta / $wall) * 100 / $cores } else { 0 }
            $highSince = $prev.HighSince

            if ($pct -ge $cpuThr) {
                if (-not $highSince) { $highSince = $now }
                elseif (((Get-Date) - $highSince).TotalSeconds -ge $cpuSec) {
                    $key = "cpu:$id"
                    if ($script:UserSettings.autoSuggestKill -and (Test-AlertCooldown -Key $key -CooldownSec $cooldown)) {
                        $script:PendingKill[$id] = $name
                        Show-Balloon -Title 'CPU eleve' -Text (
                            "$name CPU eleve. Menu: Tuer suggestions ou Mode jeu."
                        ) -Icon Warning
                        Mark-Alert -Key $key
                        $highSince = $null
                    }
                }
            }
            else { $highSince = $null }

            $script:CpuTrack[$id] = @{ CpuTime = $cpuTime; At = $now; HighSince = $highSince }

            $ramMb = $p.WorkingSet64 / 1MB
            $ramPct = ($ramMb / $script:TotalRamMb) * 100
            $ramMin = [double]$rules.ramAlertMinMb
            $ramPctThr = [double]$rules.ramAlertPercentOfSystem
            if ($ramMb -ge $ramMin -or $ramPct -ge $ramPctThr) {
                $key = "ram:$id"
                if (Test-AlertCooldown -Key $key -CooldownSec $cooldown) {
                    $ramLine = '{0} ~{1} Mo ({2}% systeme).' -f $name, [math]::Round($ramMb), [math]::Round($ramPct)
                    Show-Balloon -Title 'RAM elevee' -Text $ramLine -Icon Warning
                    Mark-Alert -Key $key
                }
            }

            if ($p.Responding -eq $false) {
                $key = "hang:$id"
                if ($script:UserSettings.autoSuggestKill -and (Test-AlertCooldown -Key $key -CooldownSec $cooldown)) {
                    $script:PendingKill[$id] = $name
                    Show-Balloon -Title 'Processus bloque' -Text ("$name - proposition via le menu de l'icone.") -Icon Error
                    Mark-Alert -Key $key
                }
            }
        }
        catch { }
    }

    $live = @{}
    Get-Process | ForEach-Object { $live[$_.Id] = $true }
    foreach ($k in @($script:CpuTrack.Keys)) {
        if (-not $live.ContainsKey($k)) { $script:CpuTrack.Remove($k) }
    }

    if ($rules.diskAlertOnlyWhenNotGaming -and $gaming) {
        $script:DiskHighSince = $null
        return
    }

    try {
        $disk = (Get-Counter -Counter '\PhysicalDisk(_Total)\% Disk Time' -ErrorAction Stop).CounterSamples.CookedValue
        $diskThr = [double]$rules.diskBusyThresholdPercent
        $diskSec = [double]$rules.diskBusySustainedSeconds
        if ($disk -ge $diskThr) {
            if (-not $script:DiskHighSince) { $script:DiskHighSince = $now }
            elseif (((Get-Date) - $script:DiskHighSince).TotalSeconds -ge $diskSec) {
                $key = 'disk:busy'
                if (Test-AlertCooldown -Key $key -CooldownSec $cooldown) {
                    $hogs = @($rules.knownDiskHogs) | ForEach-Object {
                        if (Get-Process -Name $_ -ErrorAction SilentlyContinue) { $_ }
                    }
                    $extra = if ($hogs.Count) { " Suspects: $($hogs -join ', ')" } else { '' }
                    $diskLine = 'Disque ~{0}% (hors session jeu).{1}' -f [math]::Round($disk), $extra
                    Show-Balloon -Title 'Disque sature' -Text $diskLine -Icon Warning
                    Mark-Alert -Key $key
                    $script:DiskHighSince = $null
                }
            }
        }
        else { $script:DiskHighSince = $null }
    }
    catch { }
}

function Invoke-GameModeKillNow {
    try {
        if (Get-Command Ensure-UltimatePerformanceActive -ErrorAction SilentlyContinue) {
            Ensure-UltimatePerformanceActive | Out-Null
        }
        $cfg = Get-GameModeKillConfig
        $r = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames
        $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames -LauncherFamilies $cfg.GamingLauncherFamilies
        $n = $r.Killed.Count + $idle.Killed.Count
        $extra = if ($idle.Kept.Count) { " Gardes: $($idle.Kept[0])." } else { '' }
        Show-Balloon -Title 'Mode jeu' -Text ("$n processus fermes.$extra") -Icon Info
    }
    catch {
        Show-Balloon -Title 'Mode jeu' -Text $_.Exception.Message -Icon Error
    }
}

function Invoke-IdleLaunchersOnly {
    try {
        $cfg = Get-GameModeKillConfig
        $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames -LauncherFamilies $cfg.GamingLauncherFamilies
        if ($idle.Killed.Count -eq 0) {
            $msg = if ($idle.Notes -and $idle.Notes.Count) { $idle.Notes[0] } else { 'Aucun launcher gaming superflu ouvert.' }
            Show-Balloon -Title 'Launchers' -Text $msg -Icon Info
        }
        else {
            Show-Balloon -Title 'Launchers' -Text (
                "Fermes: $($idle.Killed.Count). Gardes: $($idle.Kept -join ', ')"
            ) -Icon Info
        }
    }
    catch {
        Show-Balloon -Title 'Launchers' -Text $_.Exception.Message -Icon Error
    }
}

function Stop-PendingSuggestedProcesses {
    $n = 0
    foreach ($entry in @($script:PendingKill.GetEnumerator())) {
        try {
            Stop-Process -Id $entry.Key -Force -ErrorAction Stop
            $n++
        }
        catch { }
        $script:PendingKill.Remove($entry.Key)
    }
    Show-Balloon -Title 'Suggestions' -Text ("$n processus fermes.") -Icon Info
}

function Invoke-WatchGameSessionStart {
    $fresh = $script:FreshAppData
    if (Get-Command Get-FreshAgentGameSessionState -ErrorAction SilentlyContinue) {
        if (Get-FreshAgentGameSessionState -FreshAppData $fresh) {
            Show-Balloon -Title 'Session jeu' -Text 'Session deja active. Utilise Fin session jeu.' -Icon Warning
            return
        }
    }
    try {
        $focusSnap = Get-WindowsFocusAssistSnapshot
        $focusNotes = Set-WindowsFocusAssistBestEffort -Enable
        $prevPower = Get-ActivePowerSchemeGuid
        if (Get-Command Ensure-UltimatePerformanceActive -ErrorAction SilentlyContinue) {
            Ensure-UltimatePerformanceActive | Out-Null
        }
        $killNotes = @()
        if (Get-Command Get-GameModeKillConfig -ErrorAction SilentlyContinue) {
            $cfg = Get-GameModeKillConfig
            $result = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames
            $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames -LauncherFamilies $cfg.GamingLauncherFamilies
            $killNotes += "Fermes: $($result.Killed.Count); launchers idle: $($idle.Killed.Count)"
        }
        $state = [pscustomobject]@{
            startedAt   = (Get-Date).ToString('o')
            focusAssist = $focusSnap
            powerScheme = $prevPower
        }
        if (Get-Command Set-FreshAgentGameSessionState -ErrorAction SilentlyContinue) {
            Set-FreshAgentGameSessionState -State $state -FreshAppData $fresh
        }
        $msg = (($focusNotes + $killNotes) -join ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = 'Session jeu activee (DND + mode jeu).' }
        Show-Balloon -Title 'Session jeu' -Text $msg -Icon Info
        Update-MaintenanceTrayStatus
    }
    catch {
        Show-Balloon -Title 'Session jeu' -Text $_.Exception.Message -Icon Error
    }
}

function Invoke-WatchGameSessionEnd {
    $fresh = $script:FreshAppData
    if (-not (Get-Command Get-FreshAgentGameSessionState -ErrorAction SilentlyContinue)) {
        Show-Balloon -Title 'Session jeu' -Text 'Module session indisponible.' -Icon Warning
        return
    }
    $state = Get-FreshAgentGameSessionState -FreshAppData $fresh
    if (-not $state) {
        Show-Balloon -Title 'Session jeu' -Text 'Aucune session jeu enregistree.' -Icon Warning
        return
    }
    try {
        $notes = Restore-WindowsFocusAssistSnapshot -Snapshot $state.focusAssist
        if ($state.powerScheme) {
            if (Set-ActivePowerSchemeGuid -Guid $state.powerScheme) {
                $notes += 'Plan alimentation restaure.'
            }
        }
        Clear-FreshAgentGameSessionState -FreshAppData $fresh
        $msg = ($notes -join ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = 'Session jeu terminee.' }
        Show-Balloon -Title 'Fin session jeu' -Text $msg -Icon Info
        Update-MaintenanceTrayStatus
    }
    catch {
        Show-Balloon -Title 'Fin session jeu' -Text $_.Exception.Message -Icon Error
    }
}

function Invoke-WatchWeeklyHealthReportMenu {
    if (-not (Get-Command New-FreshAgentWeeklyHealthReport -ErrorAction SilentlyContinue)) {
        Show-Balloon -Title 'Rapport' -Text 'Module sante indisponible.' -Icon Warning
        return
    }
    try {
        $r = New-FreshAgentWeeklyHealthReport -FreshAppData $script:FreshAppData
        $msg = [string]$r.message
        if ($msg.Length -gt 220) { $msg = $msg.Substring(0, 217) + '...' }
        Show-Balloon -Title 'Rapport sante' -Text $msg -Icon Info
    }
    catch {
        Show-Balloon -Title 'Rapport sante' -Text $_.Exception.Message -Icon Error
    }
}

function Invoke-WatchTempCleanupMenu {
    if (-not (Get-Command Invoke-FreshAgentCleanup -ErrorAction SilentlyContinue)) {
        Show-Balloon -Title 'Nettoyage' -Text 'Module optimise indisponible.' -Icon Warning
        return
    }
    try {
        $r = Invoke-FreshAgentCleanup -Temp
        $msg = if ($r -and $r.message) { [string]$r.message } else { 'Nettoyage temporaires termine.' }
        if ($msg.Length -gt 220) { $msg = $msg.Substring(0, 217) + '...' }
        Show-Balloon -Title 'Nettoyage' -Text $msg -Icon Info
    }
    catch {
        Show-Balloon -Title 'Nettoyage' -Text $_.Exception.Message -Icon Error
    }
}

function Ensure-WatchAgentTrayIconFile {
  param([string]$FreshAppData = $script:FreshAppData)
    $iconPath = Join-Path $FreshAppData 'fresh-windows.ico'
    if ((Test-Path -LiteralPath $iconPath) -and ((Get-Item -LiteralPath $iconPath).Length -gt 1000)) {
        return $iconPath
    }
    $candidates = @(
        (Join-Path $PSScriptRoot '..\assets\fresh-windows.ico'),
        (Join-Path $env:LOCALAPPDATA 'FreshWindows\fresh-windows.ico')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c) -and ((Get-Item -LiteralPath $c).Length -gt 1000)) {
            try {
                Copy-Item -LiteralPath $c -Destination $iconPath -Force
                return $iconPath
            }
            catch { }
        }
    }
    $url = "$RepoRawRoot/assets/fresh-windows.ico"
    try {
        Invoke-WebRequest -Uri $url -OutFile $iconPath -UseBasicParsing -TimeoutSec 20
        if ((Test-Path -LiteralPath $iconPath) -and ((Get-Item -LiteralPath $iconPath).Length -gt 1000)) {
            return $iconPath
        }
    }
    catch {
        Write-WatchLog ("Icone download: {0}" -f $_.Exception.Message)
    }
    return $null
}

function Set-WatchAgentTrayIcon {
    if (-not $script:NotifyIcon) { return }
    $iconPath = Ensure-WatchAgentTrayIconFile
    try {
        if ($iconPath) {
            $script:NotifyIcon.Icon = New-Object System.Drawing.Icon($iconPath)
        }
        else {
            $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        }
    }
    catch {
        try { $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information } catch { }
    }
}

function Refresh-WatchAgentTrayVisibility {
    if (-not $script:NotifyIcon) { return }
    try {
        Set-WatchAgentTrayIcon
        Update-MaintenanceTrayStatus
        $script:NotifyIcon.Visible = $false
        [System.Windows.Forms.Application]::DoEvents()
        $script:NotifyIcon.Visible = $true
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch {
        Write-WatchLog ("Tray refresh: {0}" -f $_.Exception.Message)
    }
}

function Initialize-WatchAgentSystrayEarly {
    if (Test-WatchAgentSystrayLive) { return }
    Reset-WatchAgentSystrayUi
    Write-WatchLog 'Init UI (early)'
    $script:HiddenForm = New-Object System.Windows.Forms.Form
    $script:HiddenForm.Text = 'Fresh Windows Maintenance'
    $script:HiddenForm.ShowInTaskbar = $false
    $script:HiddenForm.FormBorderStyle = 'FixedToolWindow'
    $script:HiddenForm.Size = New-Object System.Drawing.Size(1, 1)
    $script:HiddenForm.StartPosition = 'Manual'
    $script:HiddenForm.Location = New-Object System.Drawing.Point(-32000, -32000)
    $script:HiddenForm.Add_FormClosed((Register-WatchUiHandler {
            if ($script:NotifyIcon) {
                $script:NotifyIcon.Visible = $false
                $script:NotifyIcon.Dispose()
                $script:NotifyIcon = $null
            }
            $script:HiddenForm = $null
            Exit-FreshWatchAgentSingleInstance
        }))

    $script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
    Set-WatchAgentTrayIcon
    $script:NotifyIcon.Text = 'Fresh Maintenance (demarrage...)'
    $script:WatchEarlyContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $miLoadEarly = $script:WatchEarlyContextMenu.Items.Add('Chargement...')
    $miLoadEarly.Enabled = $false
    $miQuitEarly = $script:WatchEarlyContextMenu.Items.Add('Quitter')
    Add-WatchMenuClick $miQuitEarly { Request-WatchAgentShutdown }
    $script:NotifyIcon.ContextMenuStrip = $script:WatchEarlyContextMenu
    $script:NotifyIcon.Visible = $true
    Write-WatchLog 'NotifyIcon visible (early)'
    try { Hide-WatchConsole } catch { }
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}

Initialize-WatchAgentSystrayEarly

function Install-WatchAgentFullTrayMenu {
    if ($script:WatchFullMenuInstalled) { return }
    Write-WatchLog 'Init UI (menu complet)'
    Update-MaintenanceTrayStatus

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $miKill = $menu.Items.Add('Mode jeu (liste + launchers inactifs)')
    Add-WatchMenuClick $miKill { Invoke-GameModeKillNow }

    $miLaunchers = $menu.Items.Add('Fermer launchers gaming inactifs')
    Add-WatchMenuClick $miLaunchers { Invoke-IdleLaunchersOnly }

    $miPending = $menu.Items.Add('Tuer suggestions en attente')
    Add-WatchMenuClick $miPending { Stop-PendingSuggestedProcesses }

    $miAuto = $menu.Items.Add('Detection auto : ON')
    $script:WatchMenuAutoItem = $miAuto
    Add-WatchMenuClick $miAuto {
        $s = Get-WatchUserSettings
        $s.autoSuggestKill = -not $s.autoSuggestKill
        Set-WatchUserSettings -Settings $s
        $script:UserSettings = $s
        $miAuto.Text = if ($s.autoSuggestKill) { 'Detection auto : ON' } else { 'Detection auto : OFF' }
    }

    $miMon = $menu.Items.Add('Surveillance : ON')
    $script:WatchMenuMonItem = $miMon
    Add-WatchMenuClick $miMon {
        $s = Get-WatchUserSettings
        $s.monitorEnabled = -not $s.monitorEnabled
        Set-WatchUserSettings -Settings $s
        $script:UserSettings = $s
        $miMon.Text = if ($s.monitorEnabled) { 'Surveillance : ON' } else { 'Surveillance : OFF' }
        Sync-WatchAgentPollTimer
    }

    $menu.Items.Add('-') | Out-Null

    $miCleanup = $menu.Items.Add('Nettoyage fichiers temporaires')
    Add-WatchMenuClick $miCleanup { Invoke-WatchTempCleanupMenu }

    $miWeekly = $menu.Items.Add('Rapport sante hebdomadaire')
    Add-WatchMenuClick $miWeekly { Invoke-WatchWeeklyHealthReportMenu }

    $menu.Items.Add('-') | Out-Null

    $miGameSession = $menu.Items.Add('Session jeu (mode jeu + DND)')
    Add-WatchMenuClick $miGameSession { Invoke-WatchGameSessionStart }

    $miEndGame = $menu.Items.Add('Fin session jeu')
    Add-WatchMenuClick $miEndGame { Invoke-WatchGameSessionEnd }

    $menu.Items.Add('-') | Out-Null
    $miExit = $menu.Items.Add('Quitter')
    Add-WatchMenuClick $miExit { Request-WatchAgentShutdown }

    $script:WatchContextMenuStrip = $menu
    if ($script:NotifyIcon) {
        $script:NotifyIcon.ContextMenuStrip = $script:WatchContextMenuStrip
    }

    if ($script:WatchMenuAutoItem) {
        $script:WatchMenuAutoItem.Text = if ($script:UserSettings.autoSuggestKill) {
            'Detection auto : ON'
        }
        else {
            'Detection auto : OFF'
        }
    }
    if ($script:WatchMenuMonItem) {
        $script:WatchMenuMonItem.Text = if ($script:UserSettings.monitorEnabled) {
            'Surveillance : ON'
        }
        else {
            'Surveillance : OFF'
        }
    }
    $script:WatchFullMenuInstalled = $true
    Write-WatchLog 'Menu complet installe'
}

function Stop-WatchAgentPollTimerIfRunning {
    if (-not $script:WatchPollTimer) { return }
    try { $script:WatchPollTimer.Stop() } catch { }
    try { $script:WatchPollTimer.Dispose() } catch { }
    $script:WatchPollTimer = $null
    Write-WatchLog 'Surveillance poll arretee'
}

function Start-WatchAgentPollTimerIfNeeded {
    if (-not $script:UserSettings.monitorEnabled) { return }
    if ($script:WatchPollTimer) { return }
    $pollMs = [math]::Max(5000, [int]$script:WatchRules.pollIntervalSeconds * 1000)
    $script:WatchPollTimer = New-Object System.Windows.Forms.Timer
    $script:WatchPollTimer.Interval = $pollMs
    $script:WatchPollTimer.Add_Tick((Register-WatchUiHandler { Invoke-WatchTick }))
    $script:WatchPollTimer.Start()
    Write-WatchLog ("Surveillance poll demarree ({0} ms)" -f $pollMs)
}

function Sync-WatchAgentPollTimer {
    if ($script:UserSettings.monitorEnabled) {
        Start-WatchAgentPollTimerIfNeeded
    }
    else {
        Stop-WatchAgentPollTimerIfRunning
    }
}

function Start-WatchAgentUiBootstrap {
    if ($script:WatchUiBootstrapStarted) { return }
    $script:WatchUiBootstrapStarted = $true
    try {
        Install-WatchAgentFullTrayMenu
        Sync-WatchAgentPollTimer
        Refresh-WatchAgentTrayVisibility
        Show-Balloon -Title 'Fresh Maintenance' -Text 'Agent actif — icone dans la zone de notification (^).' -Icon Info
        Write-WatchLog 'UI bootstrap OK'
    }
    catch {
        Write-WatchLog ("UI bootstrap: {0}" -f $_.Exception.Message)
    }
}

$script:WatchAgentExitRequested = $false
if (-not (Test-WatchAgentSystrayLive)) {
    Initialize-WatchAgentSystrayEarly
}
if ($script:WatchAgentExitRequested) {
    Write-WatchLog 'Sortie demandee avant message loop'
    exit 0
}
if (-not (Test-WatchAgentSystrayLive)) {
    Write-WatchLog 'UI systray indisponible'
    exit 1
}

$script:WatchFullMenuInstalled = $false
$script:WatchBootstrapTimer = New-Object System.Windows.Forms.Timer
$script:WatchBootstrapTimer.Interval = 200
$script:WatchBootstrapTimer.Add_Tick((Register-WatchUiHandler {
        $script:WatchBootstrapTimer.Stop()
        $script:WatchBootstrapTimer.Dispose()
        $script:WatchBootstrapTimer = $null
        Start-WatchAgentUiBootstrap
    }))
$script:WatchBootstrapTimer.Start()

if (-not $script:HiddenForm.IsDisposed -and -not $script:HiddenForm.Visible) {
    [void]$script:HiddenForm.Show()
}

Write-WatchLog 'Application.Run(form)'
try {
    [System.Windows.Forms.Application]::Run($script:HiddenForm)
}
catch {
    Write-WatchLog ("Run: {0}" -f $_.Exception.Message)
    throw
}
finally {
    try { Hide-WatchConsole } catch { }
}
