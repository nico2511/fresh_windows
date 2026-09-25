#Requires -Version 5.1
<#
.SYNOPSIS
  Agent barre des taches Fresh Windows.
.NOTES
  Prefs: %LOCALAPPDATA%\FreshWindows\watch-agent-user.json
  Lancer avec powershell.exe -STA (sinon l'icone n'apparait pas).
#>
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Continue'
$WatchLog = Join-Path $env:LOCALAPPDATA 'FreshWindows\watch-agent.log'

function Write-WatchLog {
    param([string]$Message)
    try {
        $dir = Split-Path $WatchLog
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $WatchLog -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    } catch { }
}

# FreshAppData AVANT le mutex (sinon Split-Path null).
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
$WatchLog = Join-Path $FreshAppData 'watch-agent.log'
$script:RepoRef = $RepoRef
$script:FreshAppData = $FreshAppData
$script:RepoRawRoot = $RepoRawRoot
$UserSettingsPath = Join-Path $FreshAppData 'watch-agent-user.json'
$WatchConfigUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/configs/game-mode-watch.json"
try { New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null } catch { }

function Set-WatchScriptUtf8Bom {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $text = $utf8NoBom.GetString($bytes, 3, $bytes.Length - 3)
        }
        else {
            $text = $utf8NoBom.GetString($bytes)
        }
        [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding $true))
    }
    catch { }
}

function Register-WatchUiHandler {
    param([object]$Handler)
    if (-not $script:WatchUiHandlers) {
        $script:WatchUiHandlers = New-Object System.Collections.ArrayList
    }
    if ($null -ne $Handler) {
        [void]$script:WatchUiHandlers.Add($Handler)
    }
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
        try {
            if ($sender -and $sender.Text) { $label = [string]$sender.Text }
        }
        catch { }
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

function Set-WatchAgentNotifyIconInteractive {
    if (-not $script:NotifyIcon) { return }
    $script:NotifyIcon.ContextMenuStrip = $script:WatchContextMenuStrip
    if (-not $script:WatchMouseHandlersInstalled) {
        $script:NotifyIcon.Add_MouseUp((Register-WatchUiHandler {
                param($sender, $e)
                if ($script:WatchSuppressNotifyActivation) { return }
                if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                    Write-WatchLog 'Systray MouseUp left -> dashboard'
                    Open-FreshAgentDashboardPanel
                }
            }))
        $script:NotifyIcon.Add_Click((Register-WatchUiHandler {
                if ($script:WatchSuppressNotifyActivation) { return }
                Write-WatchLog 'Systray Click -> dashboard'
                Open-FreshAgentDashboardPanel
            }))
        $script:NotifyIcon.Add_DoubleClick((Register-WatchUiHandler {
                if ($script:WatchSuppressNotifyActivation) { return }
                Write-WatchLog 'Systray DoubleClick -> dashboard'
                Open-FreshAgentDashboardPanel
            }))
        $script:WatchMouseHandlersInstalled = $true
    }
    $script:WatchSuppressNotifyActivation = $true
    try {
        $wasVisible = $script:NotifyIcon.Visible
        if ($wasVisible) { $script:NotifyIcon.Visible = $false }
        $script:NotifyIcon.Visible = $true
    }
    finally {
        $script:WatchSuppressNotifyActivation = $false
    }
}

function Reset-WatchAgentSystrayUi {
    if ($script:NotifyIcon) {
        try { $script:NotifyIcon.Visible = $false } catch { }
        try { $script:NotifyIcon.Dispose() } catch { }
        $script:NotifyIcon = $null
    }
    if ($script:HiddenForm) {
        try {
            if (-not $script:HiddenForm.IsDisposed) {
                $script:HiddenForm.Dispose()
            }
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
    catch {
        return $false
    }
}

function Request-WatchAgentShutdown {
    Write-WatchLog 'Arret agent (Exit)'
    $script:WatchAgentExitRequested = $true
    try { Stop-FreshAgentAlwaysOnVoice } catch { }
    try {
        if ($script:NotifyIcon) { $script:NotifyIcon.Visible = $false }
    }
    catch { }
    try { Exit-FreshWatchAgentSingleInstance } catch { }
    [Environment]::Exit(0)
}

function Stop-WatchAgentMessageLoop {
    try {
        if ($script:WatchAppContext) {
            $script:WatchAppContext.ExitThread()
        }
        elseif ($script:HiddenForm) {
            try {
                if (-not $script:HiddenForm.IsDisposed) {
                    $script:HiddenForm.Close()
                }
            }
            catch { }
        }
    }
    catch { }
}

Write-WatchLog 'WatchAgent start'
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
    $appData = $script:FreshAppData
    if ([string]::IsNullOrWhiteSpace($appData)) {
        $appData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
        $script:FreshAppData = $appData
    }
    $leaf = Split-Path $appData -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = 'FreshWindows' }
    $mutexName = "Global\FreshWindows-WatchAgent-$leaf"
    $script:WatchMutex = $null
    $acquired = $false
    try {
        $script:WatchMutex = New-Object System.Threading.Mutex($false, $mutexName)
        try {
            $acquired = $script:WatchMutex.WaitOne(0, $false)
        }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
            Write-WatchLog 'Mutex abandonne (crash precedent) — reprise'
        }
        if (-not $acquired) {
            $peers = @(Get-FreshWatchAgentPeerProcesses)
            if ($peers.Count -eq 0) {
                Write-WatchLog 'Mutex bloque sans processus agent — reset'
                try { $script:WatchMutex.Dispose() } catch {}
                $script:WatchMutex = $null
                $created = $false
                $script:WatchMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
                $acquired = $true
            }
            else {
                $pids = ($peers | ForEach-Object { [string]$_.ProcessId }) -join ','
                Write-WatchLog ('Autre instance active (PID {0}) — exit. Arreter: Stop-Process -Id {0} -Force' -f $pids)
                exit 0
            }
        }
        if ($acquired) {
            Write-WatchLog ("Mutex acquis PID $PID")
        }
    }
    catch {
        Write-WatchLog ("Mutex ignore : {0}" -f $_.Exception.Message)
    }
}

function Exit-FreshWatchAgentSingleInstance {
    try {
        if ($script:WatchMutex) {
            try { [void]$script:WatchMutex.ReleaseMutex() } catch {}
            try { $script:WatchMutex.Dispose() } catch {}
            $script:WatchMutex = $null
        }
    }
    catch { }
}

Enter-FreshWatchAgentSingleInstance
Write-WatchLog 'Post-mutex OK'

function Hide-WatchConsole {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FreshWinNative {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
        $hwnd = [FreshWinNative]::GetConsoleWindow()
        if ($hwnd -and $hwnd -ne [IntPtr]::Zero) {
            [void][FreshWinNative]::ShowWindow($hwnd, 0)
        }
    } catch { }
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
} catch { }

# RepoRef / FreshAppData deja initialises en tete de script (avant mutex).
Write-WatchLog ("AppData={0} Ref={1}" -f $script:FreshAppData, $script:RepoRef)

function Ensure-WatchAgentTrayIconFile {
    param([string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Join-Path $env:LOCALAPPDATA 'FreshWindows' }))
    $iconPath = Join-Path $FreshAppData 'fresh-windows.ico'
    if ((Test-Path -LiteralPath $iconPath) -and ((Get-Item -LiteralPath $iconPath).Length -gt 1000)) {
        return $iconPath
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'FreshWindows\fresh-windows.ico'),
        (Join-Path $PSScriptRoot '..\assets\fresh-windows.ico')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c) -and ((Get-Item -LiteralPath $c).Length -gt 1000)) {
            try {
                Copy-Item -LiteralPath $c -Destination $iconPath -Force
                Write-WatchLog ("Icone copiee depuis {0}" -f $c)
                return $iconPath
            }
            catch { }
        }
    }
    $ref = if ($script:RepoRef) { $script:RepoRef } else { 'main' }
    $url = "https://raw.githubusercontent.com/nico2511/fresh_windows/$ref/assets/fresh-windows.ico"
    try {
        Invoke-WebRequest -Uri $url -OutFile $iconPath -UseBasicParsing -TimeoutSec 20
        if ((Test-Path -LiteralPath $iconPath) -and ((Get-Item -LiteralPath $iconPath).Length -gt 1000)) {
            Write-WatchLog ("Icone telechargee ({0} octets)" -f (Get-Item -LiteralPath $iconPath).Length)
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
            Write-WatchLog ("Tray icon file: {0}" -f $iconPath)
        }
        else {
            # Secours visible: icone Information (pas Application, trop generique)
            $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
            Write-WatchLog 'Tray icon: SystemIcons.Information (pas de .ico)'
        }
    }
    catch {
        Write-WatchLog ("Tray icon set: {0}" -f $_.Exception.Message)
        try { $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information } catch { }
    }
}

function Refresh-WatchAgentTrayVisibility {
    if (-not $script:NotifyIcon) { return }
    try {
        Set-WatchAgentTrayIcon
        $script:NotifyIcon.Text = 'Fresh Agent'
        $script:NotifyIcon.Visible = $false
        [System.Windows.Forms.Application]::DoEvents()
        $script:NotifyIcon.Visible = $true
        [System.Windows.Forms.Application]::DoEvents()
        Write-WatchLog ("Tray Visible={0} HasIcon={1}" -f $script:NotifyIcon.Visible, ($null -ne $script:NotifyIcon.Icon))
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
    $script:HiddenForm.Text = 'Fresh Windows Watch'
    # Pas Opacity=0: certains builds Win11 n'accrochent pas le NotifyIcon.
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
    $script:NotifyIcon.Text = 'Fresh Agent (demarrage...)'
    $script:WatchEarlyContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $miLoadEarly = $script:WatchEarlyContextMenu.Items.Add('Chargement des modules...')
    $miLoadEarly.Enabled = $false
    $miQuitEarly = $script:WatchEarlyContextMenu.Items.Add('Quitter')
    Add-WatchMenuClick $miQuitEarly { Request-WatchAgentShutdown }
    $script:NotifyIcon.ContextMenuStrip = $script:WatchEarlyContextMenu
    $script:NotifyIcon.Visible = $true
    Write-WatchLog 'NotifyIcon visible (early)'
    try { Hide-WatchConsole } catch { }
    try {
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch {
        Write-WatchLog ("Early DoEvents: {0}" -f $_.Exception.Message)
    }
}

Initialize-WatchAgentSystrayEarly

$script:FreshAgentReady = $false
$script:FreshAgentModuleBootPending = $true
$script:FreshAgentAi = $null
$script:VoiceListenActive = $false
$script:MiAiListenItem = $null
$script:MiAiListenLabel = $null
$script:FaBgResultPending = $false
$script:FaBgResultLastAt = $null
$script:FaSkillResultPending = $false
$script:FaSkillResultLastAt = $null
$script:FaSkillResultId = $null
$script:FaSkillResultStarted = $null
$script:FaAiResultPending = $false
$script:FaAiResultLastAt = $null
$script:FaAiResultStarted = $null
$script:FreshAgentDeferredBootPending = $false
$faConfigCandidates = @(
    (Join-Path $FreshAppData 'lib\FreshAgent-Config.ps1'),
    (Join-Path $PSScriptRoot 'lib\FreshAgent-Config.ps1')
)
foreach ($faPath in $faConfigCandidates) {
    if ($faPath -and (Test-Path -LiteralPath $faPath)) {
        try {
            Set-WatchScriptUtf8Bom -Path $faPath
            . $faPath
            Write-WatchLog 'FreshAgent-Config charge (boot leger)'
            break
        }
        catch {
            Write-WatchLog ("FreshAgent-Config: {0}" -f $_.Exception.Message)
        }
    }
}

Write-WatchLog 'Chargement GameMode-Common'
$commonPath = $null
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $commonPath = Join-Path $PSScriptRoot 'GameMode-Common.ps1'
}
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
    $commonUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/scripts/GameMode-Common.ps1"
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
Write-WatchLog 'GameMode-Common pret'

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
        knownDiskHogs                   = @('SearchIndexer', 'MsMpEng')
    }
}

function Get-WatchRules {
    $defaults = Get-WatchRulesDefault
    try {
        $job = Start-Job -ArgumentList $WatchConfigUrl -ScriptBlock {
            param($Uri)
            Invoke-RestMethod -Uri $Uri -UseBasicParsing
        }
        if (Wait-Job -Job $job -Timeout 8) {
            $r = Receive-Job -Job $job
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            if ($r) { return $r }
        }
        else {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            Write-WatchLog 'Get-WatchRules: timeout reseau (defaults)'
        }
    }
    catch {
        Write-WatchLog ("Get-WatchRules: {0}" -f $_.Exception.Message)
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
Write-WatchLog 'Surveillance prete (avant menu)'

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
    param([string]$Title, [string]$Text, [System.Windows.Forms.ToolTipIcon]$Icon = 'Info')
    if ($script:NotifyIcon) {
        # ASCII only: BalloonTip WinForms affiche du mojibake sur accents si le .ps1 est mal lu
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

function Update-FreshAgentTrayStatus {
    if (-not $script:NotifyIcon) { return }
    $parts = [System.Collections.ArrayList]@('Fresh Agent')
    try {
        if ($script:FreshAgentAi -and $script:FreshAgentAi.enabled) { [void]$parts.Add('IA') }
        if ($script:FreshAgentAi -and $script:FreshAgentAi.rag -and $script:FreshAgentAi.rag.enabled) { [void]$parts.Add('RAG') }
        if ($script:VoiceListenActive) { [void]$parts.Add('MIC') }
        if (Get-Command Get-FreshAgentGameSessionState -ErrorAction SilentlyContinue) {
            if (Get-FreshAgentGameSessionState -FreshAppData $FreshAppData) { [void]$parts.Add('Jeu') }
        }
    }
    catch { }
    $text = ($parts -join ' | ')
    if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
    $script:NotifyIcon.Text = $text
}

function Invoke-FreshWatchAgentModuleBoot {
    if (-not $script:FreshAgentModuleBootPending) { return }
    $script:FreshAgentModuleBootPending = $false
    Write-WatchLog 'Boot modules Fresh Agent (differe)...'
    try {
        if (Get-Command Import-FreshAgentStandardModules -ErrorAction SilentlyContinue) {
            Import-FreshAgentStandardModules -FreshAppData $script:FreshAppData
        }
        elseif (Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue) {
            foreach ($mod in @(
                    'lib/FreshAgent-SkillsEngine.ps1', 'lib/FreshAgent-SkillHandlers.ps1',
                    'lib/FreshAgent-Profiles.ps1', 'lib/FreshAgent-GameSession.ps1'
                )) {
                if (-not (Import-FreshAgentModule -RelativePath $mod -FreshAppData $script:FreshAppData)) {
                    Write-WatchLog ("Module Fresh Agent absent: {0}" -f $mod)
                }
            }
        }
        Import-FreshAgentDashboardAtScriptScope | Out-Null
        if (Get-Command Ensure-FreshAgentAiBridgeLoaded -ErrorAction SilentlyContinue) {
            Ensure-FreshAgentAiBridgeLoaded -FreshAppData $script:FreshAppData | Out-Null
        }
        if (Get-Command Get-FreshAgentAiConfig -ErrorAction SilentlyContinue) {
            $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData -PreferLocal
            $script:FreshAgentReady = $true
            Write-WatchLog 'Fresh Agent modules charges (differe)'
            $script:FreshAgentDeferredBootPending = $true
        }
        if ($script:FreshAgentAiMenu) {
            $m = $script:FreshAgentAiMenu
            Update-FreshAgentAiMenu -MiAiRoot $m.Root -MiAiToggle $m.Toggle -MiOllamaState $m.OllamaState `
                -MiSttState $m.SttState -MiAiListen $m.Listen -MiTtsCycle $m.TtsCycle -MiRagToggle $m.RagToggle
            if ($script:FreshAgentReady) { $m.Root.Enabled = $true }
        }
        Update-FreshAgentTrayStatus
    }
    catch {
        Write-WatchLog ("Module boot: {0}" -f $_.Exception.Message)
    }
}

function Ensure-FreshAgentConfigLoadedForBoot {
    if (Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue) {
        return $true
    }
    foreach ($faPath in @(
            (Join-Path $script:FreshAppData 'lib\FreshAgent-Config.ps1'),
            (Join-Path $PSScriptRoot 'lib\FreshAgent-Config.ps1')
        )) {
        if (-not ($faPath -and (Test-Path -LiteralPath $faPath))) { continue }
        try {
            Set-WatchScriptUtf8Bom -Path $faPath
            if (Get-Command Import-FreshAgentFileIntoScriptScope -ErrorAction SilentlyContinue) {
                Import-FreshAgentFileIntoScriptScope -LiteralPath $faPath
            }
            else { . $faPath }
            Write-WatchLog 'FreshAgent-Config recharge (boot modules)'
            return [bool](Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue)
        }
        catch {
            Write-WatchLog ("FreshAgent-Config recharge: {0}" -f $_.Exception.Message)
        }
    }
    return $false
}

function Complete-WatchAgentModuleBoot {
    try {
        Write-WatchLog 'Module boot: finalisation...'
        if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
            Write-WatchLog 'Module boot: dashboard charge (script)'
            Invoke-WatchAgentDotModuleAtScript -RelativePath 'lib/FreshAgent-Dashboard.ps1' | Out-Null
        }
        if (Get-Command Get-FreshAgentAiConfig -ErrorAction SilentlyContinue) {
            $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData -PreferLocal
            $script:FreshAgentReady = $true
            Write-WatchLog 'Fresh Agent modules charges (differe)'
            $script:FreshAgentDeferredBootPending = $true
        }
        else {
            Write-WatchLog 'Module boot: Get-FreshAgentAiConfig indisponible'
        }
        if ($script:FreshAgentAiMenu) {
            $m = $script:FreshAgentAiMenu
            Update-FreshAgentAiMenu -MiAiRoot $m.Root -MiAiToggle $m.Toggle -MiOllamaState $m.OllamaState `
                -MiSttState $m.SttState -MiAiListen $m.Listen -MiTtsCycle $m.TtsCycle -MiRagToggle $m.RagToggle `
                -SkipNetworkChecks
            if ($script:FreshAgentReady) { $m.Root.Enabled = $true }
        }
        Update-FreshAgentTrayStatus
        Start-WatchAgentPollTimerIfNeeded
        # Vague 1: pas d'auto-start voix (WhisperLoop legacy quarantine). Ecoute = bouton explicite (vague 2).
        Write-WatchLog 'Module boot: voice auto-start disabled (quarantine)'
    }
    catch {
        Write-WatchLog ("Module boot finalisation: {0}" -f $_.Exception.Message)
    }
}

function Invoke-WatchAgentDotModuleAtScript {
    param([string]$RelativePath)
    if (-not $RelativePath) { return $true }
    $rel = $RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    $path = Join-Path $script:FreshAppData $rel
    if (-not (Test-Path -LiteralPath $path)) {
        Write-WatchLog ("Module path absent: {0}" -f $path)
        return $false
    }
    try {
        Set-WatchScriptUtf8Bom -Path $path
        if (Get-Command Import-FreshAgentFileIntoScriptScope -ErrorAction SilentlyContinue) {
            Import-FreshAgentFileIntoScriptScope -LiteralPath $path
        }
        else {
            $raw = [System.IO.File]::ReadAllText($path)
            $raw = [regex]::Replace($raw, '(?m)^(\s*)#Requires[^\r\n]*', '${1}# requires stripped')
            $raw = [regex]::Replace($raw, '(?m)^(\s*)function\s+(?!script:)([A-Za-z_][\w-]*)', '${1}function script:${2}')
            Invoke-Expression $raw
        }
        return $true
    }
    catch {
        Write-WatchLog ("Module dot: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Ensure-FreshAgentSttLoaded {
    if (Get-Command Invoke-WindowsSttListenInteractive -ErrorAction SilentlyContinue) {
        return $true
    }
    $path = Join-Path $script:FreshAppData 'ai\Windows-Stt.ps1'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-WatchLog ("STT file absent: {0}" -f $path)
        return $false
    }
    try {
        if (Get-Command Import-FreshAgentFileIntoScriptScope -ErrorAction SilentlyContinue) {
            Import-FreshAgentFileIntoScriptScope -LiteralPath $path
        }
        else {
            $raw = [System.IO.File]::ReadAllText($path)
            $raw = [regex]::Replace($raw, '(?m)^(\s*)#Requires[^\r\n]*', '${1}# requires stripped')
            $raw = [regex]::Replace($raw, '(?m)^(\s*)function\s+(?!script:)([A-Za-z_][\w-]*)', '${1}function script:${2}')
            Invoke-Expression $raw
        }
        Write-WatchLog 'STT module force-loaded'
    }
    catch {
        Write-WatchLog ("STT force-load: {0}" -f $_.Exception.Message)
        return $false
    }
    return [bool](Get-Command Invoke-WindowsSttListenInteractive -ErrorAction SilentlyContinue)
}

function Invoke-WatchAgentModuleBootStep {
    if (-not $script:WatchModuleBootPlan) { return $false }
    $idx = $script:WatchModuleBootIndex
    if ($idx -ge $script:WatchModuleBootPlan.Count) {
        Complete-WatchAgentModuleBoot
        $script:WatchModuleBootPlan = $null
        $script:WatchModuleBootIndex = 0
        return $false
    }
    $step = $script:WatchModuleBootPlan[$idx]
    $script:WatchModuleBootIndex = $idx + 1
    if ($step.Rel) {
        Write-WatchLog ("Module boot: {0}" -f $step.Rel)
        if (-not (Invoke-WatchAgentDotModuleAtScript -RelativePath $step.Rel)) {
            Write-WatchLog ("Module Fresh Agent absent: {0}" -f $step.Rel)
        }
    }
    return $true
}

function Start-WatchAgentModuleBootAsync {
    if (-not $script:FreshAgentModuleBootPending) { return }
    if ($script:WatchModuleBootTimer) { return }

    if (-not (Ensure-FreshAgentConfigLoadedForBoot)) {
        Write-WatchLog 'Boot modules: FreshAgent-Config / Import-FreshAgentModule indisponible'
        $script:FreshAgentModuleBootPending = $false
        return
    }

    $script:FreshAgentModuleBootPending = $false
    Write-WatchLog 'Boot modules Fresh Agent (async UI)...'

    $script:WatchModuleBootPlan = @(
        @{ Rel = 'lib/FreshAgent-SkillsEngine.ps1' },
        @{ Rel = 'lib/FreshAgent-SkillHandlers.ps1' },
        @{ Rel = 'lib/FreshAgent-GameSession.ps1' },
        @{ Rel = 'lib/FreshAgent-Inventory.ps1' },
        @{ Rel = 'lib/FreshAgent-Rag.ps1' },
        @{ Rel = 'lib/FreshAgent-History.ps1' },
        @{ Rel = 'lib/FreshAgent-Profiles.ps1' },
        @{ Rel = 'lib/FreshAgent-Log.ps1' },
        @{ Rel = 'lib/FreshAgent-Dashboard.ps1' },
        @{ Rel = 'lib/FreshAgent-Overlay.ps1' },
        @{ Rel = 'lib/FreshAgent-VoiceRouter.ps1' },
        @{ Rel = 'lib/FreshAgent-IdleSuggest.ps1' },
        @{ Rel = 'ai/Ollama-Manager.ps1' },
        @{ Rel = 'ai/FreshAgent-OllamaBridge.ps1' },
        @{ Rel = 'ai/Windows-Stt.ps1' },
        @{ Rel = 'ai/FreshAgent-Tts.ps1' },
        @{ Rel = 'ai/FreshAgent-VoiceWorker.ps1' },
        @{ Rel = $null }
    )
    $script:WatchModuleBootIndex = 0

    $script:WatchModuleBootTimer = New-Object System.Windows.Forms.Timer
    $script:WatchModuleBootTimer.Interval = 120
    $script:WatchModuleBootTimer.Add_Tick((Register-WatchUiHandler {
            try {
                $more = Invoke-WatchAgentModuleBootStep
                if (-not $more) {
                    $script:WatchModuleBootTimer.Stop()
                    $script:WatchModuleBootTimer.Dispose()
                    $script:WatchModuleBootTimer = $null
                }
            }
            catch {
                Write-WatchLog ("Module boot step: {0}" -f $_.Exception.Message)
            }
        }))
    $script:WatchModuleBootTimer.Start()
}

function Invoke-FreshAgentDeferredBoot {
    if (-not $script:FreshAgentDeferredBootPending) { return }
    $script:FreshAgentDeferredBootPending = $false
    if (-not $script:FreshAgentReady) { return }
    if (Get-Command Build-FreshAgentMachineInventory -ErrorAction SilentlyContinue) {
        try {
            $invPath = Get-FreshAgentInventoryPath -FreshAppData $script:FreshAppData
            if (-not (Test-Path -LiteralPath $invPath)) {
                Build-FreshAgentMachineInventory -FreshAppData $script:FreshAppData | Out-Null
                Write-WatchLog 'Inventaire machine initialise (differe)'
            }
        }
        catch {
            Write-WatchLog ("Inventaire: {0}" -f $_.Exception.Message)
        }
    }
    if ($script:FreshAgentAi -and $script:FreshAgentAi.rag -and $script:FreshAgentAi.rag.enabled -and (Get-Command Build-FreshAgentRagIndex -ErrorAction SilentlyContinue)) {
        try {
            $ragPath = Get-FreshAgentRagIndexPath -FreshAppData $script:FreshAppData
            if (-not (Test-Path -LiteralPath $ragPath)) {
                Build-FreshAgentRagIndex -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData | Out-Null
                Write-WatchLog 'Index RAG initialise (differe)'
            }
        }
        catch {
            Write-WatchLog ("RAG: {0}" -f $_.Exception.Message)
        }
    }
}

function Invoke-WatchTick {
    if ($script:WatchModuleBootTimer -or $script:WatchModuleBootPlan) {
        return
    }
    if ($script:WatchRulesRemotePending) {
        $script:WatchRulesRemotePending = $false
        $script:WatchRules = Get-WatchRules
    }
    $script:UserSettings = Get-WatchUserSettings
    Update-FreshAgentTrayStatus
    if ($script:FreshAgentModuleBootPending) {
        Start-WatchAgentModuleBootAsync
    }
    Invoke-FreshAgentDeferredBoot
    Invoke-FreshAgentBackgroundResultPoll
    $skillPoll = $script:FreshAgentSkillResultPoll
    if ($skillPoll -is [scriptblock]) { & $skillPoll }
    elseif (Get-Command Invoke-FreshAgentSkillResultPoll -ErrorAction SilentlyContinue) {
        Invoke-FreshAgentSkillResultPoll
    }
    if (Get-Command Update-FreshAgentDashboardIfOpen -ErrorAction SilentlyContinue) {
        Update-FreshAgentDashboardIfOpen
    }
    if (Get-Command Invoke-FreshAgentIdleSuggestTick -ErrorAction SilentlyContinue) {
        try {
            Invoke-FreshAgentIdleSuggestTick -FreshAppData $script:FreshAppData -RepoRef $script:RepoRef -AiConfig $script:FreshAgentAi
        }
        catch { }
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
                        Show-Balloon -Title 'CPU eleve (hors jeu/comm)' -Text (
                            "$name CPU eleve. Clic droit: Tuer suggestion ou Mode jeu."
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

            # SystemSettings et co. reportent souvent Responding=false a tort
            if ($p.Responding -eq $false) {
                $key = "hang:$id"
                if ($script:UserSettings.autoSuggestKill -and (Test-AlertCooldown -Key $key -CooldownSec $cooldown)) {
                    $script:PendingKill[$id] = $name
                    Show-Balloon -Title 'Processus ne repond pas' -Text ("$name - proposition de fermeture via le menu de l'icone.") -Icon Error
                    Mark-Alert -Key $key
                }
            }
        }
        catch { }
    }

    # Nettoyage PIDs morts
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
                    $extra = if ($hogs.Count) { "`nSuspects : $($hogs -join ', ')" } else { '' }
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
        Ensure-UltimatePerformanceActive | Out-Null
        $cfg = Get-GameModeKillConfig
        $r = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames
        $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames -LauncherFamilies $cfg.GamingLauncherFamilies
        $n = $r.Killed.Count + $idle.Killed.Count
        $extra = if ($idle.Kept.Count) { " Gardes : $($idle.Kept[0])." } else { '' }
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
                "Fermes : $($idle.Killed.Count). Gardes : $($idle.Kept -join ', ')"
            ) -Icon Info
        }
    }
    catch {
        Show-Balloon -Title 'Launchers' -Text $_.Exception.Message -Icon Error
    }
}

function Test-LocalScriptsStale {
    $refFile = Join-Path $FreshAppData 'scripts.ref'
    if (-not (Test-Path -LiteralPath $refFile)) { return $true }
    try {
        return ((Get-Content -LiteralPath $refFile -Raw -Encoding UTF8).Trim() -ne $RepoRef)
    }
    catch { return $true }
}

function Ensure-FreshAgentProfileReady {
    # Check rapide uniquement (pas de re-import synchrone sur le thread UI).
    if (Get-Command Invoke-FreshAgentProfile -ErrorAction SilentlyContinue) {
        return $true
    }
    return (Test-Path -LiteralPath (Join-Path $script:FreshAppData 'lib\FreshAgent-Profiles.ps1'))
}

function Invoke-FreshAgentProfileFromUi {
    param([string]$ProfileId)
    $sb = $script:FreshAgentStartProfileBg
    if ($sb -is [scriptblock]) {
        & $sb $ProfileId
        return
    }
    Start-FreshAgentUiProfileBackground -ProfileId $ProfileId
}

function Start-FreshAgentUiProfileBackground {
    param([Parameter(Mandatory)][string]$ProfileId)
    Write-WatchLog ("Profile bg enter: {0}" -f $ProfileId)
    if (-not $script:FreshAgentReady) {
        Show-Balloon -Title 'Profil' -Text 'Modules non charges.' -Icon Warning
        return
    }
    if ($script:FaSkillResultPending) {
        Show-Balloon -Title 'Profil' -Text 'Une action skill/profil est deja en cours.' -Icon Warning
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $script:FreshAppData 'lib\FreshAgent-Profiles.ps1'))) {
        Show-Balloon -Title 'Profil' -Text 'FreshAgent-Profiles absent — sync scripts locaux.' -Icon Warning
        return
    }

    Write-WatchLog ("Profile bg start: {0}" -f $ProfileId)
    Show-Balloon -Title 'Profil' -Text ("Profil en cours: {0}" -f $ProfileId) -Icon Info

    $resultPath = Join-Path $script:FreshAppData 'fa-skill-result.json'
    try { Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue } catch { }
    $freshEsc = $script:FreshAppData.Replace("'", "''")
    $repoEsc = $script:RepoRef.Replace("'", "''")
    $profEsc = $ProfileId.Replace("'", "''")
    $scriptBody = @"
`$ErrorActionPreference = 'Continue'
`$fresh = '$freshEsc'
`$repo = '$repoEsc'
`$profileId = '$profEsc'
`$resultPath = Join-Path `$fresh 'fa-skill-result.json'
`$log = Join-Path `$fresh 'watch-agent.log'
function Log([string]`$m) { try { Add-Content -LiteralPath `$log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' PROFILE ' + `$m) -Encoding UTF8 } catch {} }
try {
  . (Join-Path `$fresh 'lib\FreshAgent-Config.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-SkillsEngine.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-SkillHandlers.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-GameSession.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-Inventory.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-Profiles.ps1')
  Log ("invoke begin `$profileId")
  `$r = Invoke-FreshAgentProfile -ProfileId `$profileId -RepoRef `$repo -FreshAppData `$fresh
  `$payload = @{
    ok = [bool]`$r.ok
    message = if (`$r.message) { [string]`$r.message } else { 'OK' }
    skill = ('profile:' + `$profileId)
    at = (Get-Date -Format o)
  }
  `$payload | ConvertTo-Json -Compress | Set-Content -LiteralPath `$resultPath -Encoding UTF8
  Log ("invoke end `$profileId ok=`$(`$payload.ok)")
}
catch {
  Log ("invoke fail `$profileId : `$(`$_.Exception.Message)")
  @{ ok = `$false; message = `$_.Exception.Message; skill = ('profile:' + `$profileId); at = (Get-Date -Format o) } |
    ConvertTo-Json -Compress | Set-Content -LiteralPath `$resultPath -Encoding UTF8
}
"@
    try {
        Start-FreshAgentDetachedPs1 -ScriptContent $scriptBody
    }
    catch {
        Write-WatchLog ("Profile bg spawn: {0}" -f $_.Exception.ToString())
        Show-Balloon -Title 'Profil' -Text $_.Exception.Message -Icon Error
        return
    }
    $script:FaSkillResultPending = $true
    $script:FaSkillResultStarted = Get-Date
    $script:FaSkillResultId = "profile:$ProfileId"
    $script:FaSkillResultLastAt = $null
    Start-FreshAgentSkillPollTimerIfNeeded
    Write-WatchLog ("Profile bg queued: {0}" -f $ProfileId)
}

$script:FreshAgentStartProfileBg = {
    param([string]$ProfileId)
    Start-FreshAgentUiProfileBackground -ProfileId $ProfileId
}

function Invoke-FreshAgentSkillMenu {
    param(
        [Parameter(Mandatory)]
        [string]$SkillId,
        [hashtable]$Parameters = @{}
    )
    $sb = $script:FreshAgentStartSkillBg
    if ($sb -is [scriptblock]) {
        & $sb $SkillId $Parameters
        return
    }
    Start-FreshAgentUiSkillBackground -SkillId $SkillId -Parameters $Parameters
}

function Start-FreshAgentUiSkillBackground {
    param(
        [Parameter(Mandatory)]
        [string]$SkillId,
        [hashtable]$Parameters = @{}
    )
    Write-WatchLog ("Skill bg enter: {0}" -f $SkillId)
    if (-not $script:FreshAgentReady) {
        Show-Balloon -Title 'Fresh Agent' -Text 'Modules skills non charges (sync scripts locaux).' -Icon Warning
        return
    }
    if ($script:FaSkillResultPending) {
        Show-Balloon -Title 'Fresh Agent' -Text 'Un skill est deja en cours.' -Icon Warning
        return
    }

    Write-WatchLog ("Skill bg start: {0}" -f $SkillId)
    Show-Balloon -Title 'Fresh Agent' -Text ("Skill en cours: {0}" -f $SkillId) -Icon Info

    $resultPath = Join-Path $script:FreshAppData 'fa-skill-result.json'
    try { Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue } catch { }

    $freshEsc = $script:FreshAppData.Replace("'", "''")
    $repoEsc = $script:RepoRef.Replace("'", "''")
    $skillEsc = $SkillId.Replace("'", "''")
    $paramsJson = '{}'
    try {
        if ($Parameters -and $Parameters.Count -gt 0) {
            $paramsJson = ($Parameters | ConvertTo-Json -Compress -Depth 6)
        }
    }
    catch { $paramsJson = '{}' }
    $paramsEsc = $paramsJson.Replace("'", "''")

    $scriptBody = @"
`$ErrorActionPreference = 'Continue'
`$fresh = '$freshEsc'
`$repo = '$repoEsc'
`$skillId = '$skillEsc'
`$resultPath = Join-Path `$fresh 'fa-skill-result.json'
`$log = Join-Path `$fresh 'watch-agent.log'
function Log([string]`$m) { try { Add-Content -LiteralPath `$log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' SKILL ' + `$m) -Encoding UTF8 } catch {} }
try {
  . (Join-Path `$fresh 'lib\FreshAgent-Config.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-SkillsEngine.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-SkillHandlers.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-GameSession.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-Inventory.ps1')
  `$params = @{}
  try {
    `$rawParams = '$paramsEsc' | ConvertFrom-Json
    if (`$rawParams) {
      `$rawParams.PSObject.Properties | ForEach-Object { `$params[`$_.Name] = `$_.Value }
    }
  } catch {}
  Log ("invoke begin `$skillId")
  `$r = Invoke-FreshAgentSkill -SkillId `$skillId -Parameters `$params -RepoRef `$repo -FreshAppData `$fresh
  `$payload = @{
    ok = [bool]`$r.ok
    message = if (`$r.message) { [string]`$r.message } else { 'Termine.' }
    skill = `$skillId
    at = (Get-Date -Format o)
  }
  `$payload | ConvertTo-Json -Compress | Set-Content -LiteralPath `$resultPath -Encoding UTF8
  Log ("invoke end `$skillId ok=`$(`$payload.ok)")
}
catch {
  Log ("invoke fail `$skillId : `$(`$_.Exception.Message)")
  @{ ok = `$false; message = `$_.Exception.Message; skill = `$skillId; at = (Get-Date -Format o) } |
    ConvertTo-Json -Compress | Set-Content -LiteralPath `$resultPath -Encoding UTF8
}
"@
    try {
        Start-FreshAgentDetachedPs1 -ScriptContent $scriptBody
    }
    catch {
        Write-WatchLog ("Skill bg spawn: {0}" -f $_.Exception.ToString())
        Show-Balloon -Title 'Fresh Agent' -Text $_.Exception.Message -Icon Error
        return
    }
    $script:FaSkillResultPending = $true
    $script:FaSkillResultStarted = Get-Date
    $script:FaSkillResultId = $SkillId
    $script:FaSkillResultLastAt = $null
    Start-FreshAgentSkillPollTimerIfNeeded
    Write-WatchLog ("Skill bg queued: {0}" -f $SkillId)
}

# Publie sur $script: pour handlers WinForms / InvokeScript (pas de Function:).
$script:FreshAgentStartSkillBg = {
    param(
        [string]$SkillId,
        [hashtable]$Parameters = @{}
    )
    Start-FreshAgentUiSkillBackground -SkillId $SkillId -Parameters $Parameters
}

function Start-FreshAgentSkillPollTimerIfNeeded {
    if ($script:FaSkillPollTimer) { return }
    try {
        $script:FaSkillPollTimer = New-Object System.Windows.Forms.Timer
        $script:FaSkillPollTimer.Interval = 1000
        $script:FaSkillPollTimer.Add_Tick((Register-WatchUiHandler {
                try {
                    $poll = $script:FreshAgentSkillResultPoll
                    if ($poll -is [scriptblock]) {
                        & $poll
                    }
                    elseif ($script:WatchAgentSessionState) {
                        $null = $script:WatchAgentSessionState.InvokeCommand.InvokeScript(
                            $false, { Invoke-FreshAgentSkillResultPoll }, $null, @())
                    }
                    if (-not $script:FaSkillResultPending -and $script:FaSkillPollTimer) {
                        $script:FaSkillPollTimer.Stop()
                        $script:FaSkillPollTimer.Dispose()
                        $script:FaSkillPollTimer = $null
                    }
                }
                catch {
                    try {
                        $log = $script:FreshAgentUiLog
                        if ($log -is [scriptblock]) {
                            & $log ("Skill poll timer: {0}" -f $_.Exception.Message)
                        }
                        else {
                            Write-WatchLog ("Skill poll timer: {0}" -f $_.Exception.Message)
                        }
                    }
                    catch { }
                }
            }))
        $script:FaSkillPollTimer.Start()
    }
    catch {
        Write-WatchLog ("Skill poll timer start: {0}" -f $_.Exception.Message)
    }
}

function Invoke-FreshAgentSkillResultPoll {
    if (-not $script:FaSkillResultPending) { return }
    $path = Join-Path $script:FreshAppData 'fa-skill-result.json'
    $timeoutSec = 60
    try {
        if ($script:FaSkillResultStarted -and ((Get-Date) - $script:FaSkillResultStarted).TotalSeconds -ge $timeoutSec) {
            $script:FaSkillResultPending = $false
            Write-WatchLog ("Skill bg timeout: {0}" -f $script:FaSkillResultId)
            Show-Balloon -Title 'Fresh Agent' -Text ("Skill timeout: {0}" -f $script:FaSkillResultId) -Icon Warning
            return
        }
    }
    catch { }

    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.at -and $raw.at -eq $script:FaSkillResultLastAt) { return }
        $script:FaSkillResultLastAt = [string]$raw.at
        $script:FaSkillResultPending = $false
        $msg = if ($raw.message) { [string]$raw.message } else { 'Termine.' }
        $icon = if ($raw.ok) { 'Info' } else { 'Warning' }
        Write-WatchLog ("Skill bg done: {0} ok={1}" -f $script:FaSkillResultId, [bool]$raw.ok)
        Show-Balloon -Title 'Fresh Agent' -Text $msg -Icon $icon
        try {
            if ($raw.ok -and (Get-Command Invoke-FreshAgentSpeakSkillResult -ErrorAction SilentlyContinue)) {
                $cfg = Get-FreshAgentAiConfig -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData -PreferLocal
                Invoke-FreshAgentSpeakSkillResult -Result @{ ok = [bool]$raw.ok; message = $msg } -AiConfig $cfg -FreshAppData $script:FreshAppData
            }
        }
        catch {
            Write-WatchLog ("Skill TTS: {0}" -f $_.Exception.Message)
        }
    }
    catch {
        Write-WatchLog ("Skill bg poll: {0}" -f $_.Exception.Message)
    }
}

$script:FreshAgentSkillResultPoll = {
    if (-not $script:FaSkillResultPending) { return }
    $path = Join-Path $script:FreshAppData 'fa-skill-result.json'
    $timeoutSec = 60
    try {
        if ($script:FaSkillResultStarted -and ((Get-Date) - $script:FaSkillResultStarted).TotalSeconds -ge $timeoutSec) {
            $script:FaSkillResultPending = $false
            $log = $script:FreshAgentUiLog
            if ($log -is [scriptblock]) { & $log ("Skill bg timeout: {0}" -f $script:FaSkillResultId) }
            Show-Balloon -Title 'Fresh Agent' -Text ("Skill timeout: {0}" -f $script:FaSkillResultId) -Icon Warning
            return
        }
    }
    catch { }
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.at -and $raw.at -eq $script:FaSkillResultLastAt) { return }
        $script:FaSkillResultLastAt = [string]$raw.at
        $script:FaSkillResultPending = $false
        $msg = if ($raw.message) { [string]$raw.message } else { 'Termine.' }
        $icon = if ($raw.ok) { 'Info' } else { 'Warning' }
        $log = $script:FreshAgentUiLog
        if ($log -is [scriptblock]) { & $log ("Skill bg done: {0} ok={1}" -f $script:FaSkillResultId, [bool]$raw.ok) }
        Show-Balloon -Title 'Fresh Agent' -Text $msg -Icon $icon
    }
    catch {
        $log = $script:FreshAgentUiLog
        if ($log -is [scriptblock]) { & $log ("Skill bg poll: {0}" -f $_.Exception.Message) }
    }
}

function Show-FreshAgentAiPromptDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Fresh Agent - Tester l IA'
    $form.Size = New-Object System.Drawing.Size(480, 200)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.ShowInTaskbar = $true
    try {
        if ($script:FreshAgentDashboardForm -and -not $script:FreshAgentDashboardForm.IsDisposed) {
            $form.Owner = $script:FreshAgentDashboardForm
        }
        elseif ($script:HiddenForm -and -not $script:HiddenForm.IsDisposed) {
            $form.Owner = $script:HiddenForm
        }
    }
    catch { }

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Demande (ex: etat systeme, mets du lofi sur YouTube) :'
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(12, 12)
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(12, 36)
    $textBox.Size = New-Object System.Drawing.Size(440, 80)
    $textBox.Multiline = $true
    $textBox.ScrollBars = 'Vertical'
    $form.Controls.Add($textBox)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Envoyer'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(296, 126)
    $form.AcceptButton = $ok
    $form.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Annuler'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object System.Drawing.Point(377, 126)
    $form.CancelButton = $cancel
    $form.Controls.Add($cancel)

    $result = $form.ShowDialog()
    try { $form.Dispose() } catch { }
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $textBox.Text.Trim()
    }
    return $null
}

function Start-FreshAgentDetachedPs1 {
    param(
        [Parameter(Mandatory)]
        [string]$ScriptContent,
        [switch]$Sta
    )
    $dir = Join-Path $script:FreshAppData 'temp'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir ("fa-bg-{0}.ps1" -f ([guid]::NewGuid().ToString('n')))
    Set-Content -LiteralPath $path -Value $ScriptContent -Encoding UTF8
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($Sta) { $argList += '-STA' }
    $argList += @('-File', $path)
    Start-Process -FilePath $psExe -WindowStyle Hidden -ArgumentList $argList | Out-Null
}

function Test-FreshAgentOllamaWorkerReady {
    $worker = Join-Path $script:FreshAppData 'ai\FreshAgent-BackgroundWorker.ps1'
    $mgr = Join-Path $script:FreshAppData 'ai\Ollama-Manager.ps1'
    if ((Test-Path -LiteralPath $worker) -and (Test-Path -LiteralPath $mgr)) {
        return $true
    }
    if (Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue) {
        Import-FreshAgentModule -RelativePath 'ai/Ollama-Manager.ps1' -FreshAppData $script:FreshAppData | Out-Null
    }
    return ((Test-Path -LiteralPath $worker) -and (Test-Path -LiteralPath $mgr))
}

function Start-FreshAgentAiPromptBackground {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )
    if ([string]::IsNullOrWhiteSpace($Prompt)) { return }
    if ($script:FaAiResultPending) {
        Show-Balloon -Title 'Fresh Agent IA' -Text 'Une analyse IA est deja en cours.' -Icon Warning
        return
    }

    Write-WatchLog ("AI prompt bg start ({0} chars)" -f $Prompt.Length)
    New-Item -ItemType Directory -Path $script:FreshAppData -Force | Out-Null
    $promptFile = Join-Path $script:FreshAppData 'ai-prompt.pending.txt'
    Set-Content -LiteralPath $promptFile -Value $Prompt -Encoding UTF8
    $resultPath = Join-Path $script:FreshAppData 'fa-ai-result.json'
    try { Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue } catch { }

    Show-Balloon -Title 'Fresh Agent IA' -Text 'Analyse en cours (Ollama)...' -Icon Info

    $freshEsc = $script:FreshAppData.Replace("'", "''")
    $repoEsc = $script:RepoRef.Replace("'", "''")
    $scriptBody = @"
`$ErrorActionPreference = 'Continue'
`$fresh = '$freshEsc'
`$repo = '$repoEsc'
`$resultPath = Join-Path `$fresh 'fa-ai-result.json'
`$log = Join-Path `$fresh 'watch-agent.log'
function Log([string]`$m) { try { Add-Content -LiteralPath `$log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' AI ' + `$m) -Encoding UTF8 } catch {} }
function Write-AiResult([bool]`$Ok, [string]`$Message, `$Skills) {
  `$payload = @{
    ok = `$Ok
    message = `$Message
    skills = @(`$Skills)
    at = (Get-Date -Format o)
  }
  `$payload | ConvertTo-Json -Compress -Depth 6 | Set-Content -LiteralPath `$resultPath -Encoding UTF8
}
try {
  Log 'worker begin'
  . (Join-Path `$fresh 'lib\FreshAgent-Config.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-SkillsEngine.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-SkillHandlers.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-GameSession.ps1')
  . (Join-Path `$fresh 'ai\Ollama-Manager.ps1')
  . (Join-Path `$fresh 'ai\FreshAgent-OllamaBridge.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-Inventory.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-Rag.ps1')
  . (Join-Path `$fresh 'ai\FreshAgent-Tts.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-History.ps1')
  `$prompt = Get-Content -LiteralPath (Join-Path `$fresh 'ai-prompt.pending.txt') -Raw -Encoding UTF8
  `$cfg = Get-FreshAgentAiConfig -RepoRef `$repo -FreshAppData `$fresh -PreferLocal
  if (-not `$cfg.enabled) { throw 'IA desactivee - active IA : ON dans le panneau.' }
  if (-not (Test-OllamaApi -TimeoutSec 2)) { throw 'Ollama API injoignable (127.0.0.1:11434).' }
  Log 'Invoke-FreshAgentAiTurn...'
  `$r = Invoke-FreshAgentAiTurn -UserPrompt `$prompt.Trim() -AiConfig `$cfg -RepoRef `$repo -FreshAppData `$fresh
  `$text = if (`$r.message) { [string]`$r.message } else { 'Termine.' }
  if (`$r.skills -and `$r.skills.Count -gt 0) { `$text += ([Environment]::NewLine + 'Skills: ' + (`$r.skills -join ', ')) }
  Log ("done ok=`$(`$r.ok) len=`$(`$text.Length)")
  if (Get-Command Invoke-FreshAgentSpeak -ErrorAction SilentlyContinue) {
    try { Invoke-FreshAgentSpeak -Text `$text -AiConfig `$cfg -FreshAppData `$fresh | Out-Null } catch { Log ("tts: `$(`$_.Exception.Message)") }
  }
  if (Get-Command Add-FreshAgentAiHistoryEntry -ErrorAction SilentlyContinue) {
    try { Add-FreshAgentAiHistoryEntry -Prompt `$prompt.Trim() -Response `$text -Skills `$r.skills -FreshAppData `$fresh } catch {}
  }
  Write-AiResult -Ok ([bool]`$r.ok) -Message `$text -Skills `$r.skills
}
catch {
  Log ("fail: `$(`$_.Exception.Message)")
  Write-AiResult -Ok `$false -Message `$_.Exception.Message -Skills @()
}
"@
    try {
        Start-FreshAgentDetachedPs1 -ScriptContent $scriptBody
    }
    catch {
        Write-WatchLog ("AI prompt spawn: {0}" -f $_.Exception.ToString())
        Show-Balloon -Title 'Fresh Agent IA' -Text $_.Exception.Message -Icon Error
        return
    }
    $script:FaAiResultPending = $true
    $script:FaAiResultStarted = Get-Date
    $script:FaAiResultLastAt = $null
    Start-FreshAgentAiPollTimerIfNeeded
    Write-WatchLog 'AI prompt bg queued'
}

function Start-FreshAgentAiPollTimerIfNeeded {
    if ($script:FaAiPollTimer) { return }
    try {
        $script:FaAiPollTimer = New-Object System.Windows.Forms.Timer
        $script:FaAiPollTimer.Interval = 1000
        $script:FaAiPollTimer.Add_Tick((Register-WatchUiHandler {
                try {
                    $poll = $script:FreshAgentAiResultPoll
                    if ($poll -is [scriptblock]) { & $poll }
                    if (-not $script:FaAiResultPending -and $script:FaAiPollTimer) {
                        $script:FaAiPollTimer.Stop()
                        $script:FaAiPollTimer.Dispose()
                        $script:FaAiPollTimer = $null
                    }
                }
                catch { }
            }))
        $script:FaAiPollTimer.Start()
    }
    catch { }
}

$script:FreshAgentAiResultPoll = {
    if (-not $script:FaAiResultPending) { return }
    $path = Join-Path $script:FreshAppData 'fa-ai-result.json'
    try {
        if ($script:FaAiResultStarted -and ((Get-Date) - $script:FaAiResultStarted).TotalSeconds -ge 180) {
            $script:FaAiResultPending = $false
            $script:SttUnpauseAt = (Get-Date).AddSeconds(2)
            Write-WatchLog 'AI prompt timeout 180s'
            Show-Balloon -Title 'Fresh Agent IA' -Text 'Timeout analyse IA (180s). Verifie Ollama / modele.' -Icon Warning
            return
        }
    }
    catch { }
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.at -and $raw.at -eq $script:FaAiResultLastAt) { return }
        $script:FaAiResultLastAt = [string]$raw.at
        $script:FaAiResultPending = $false
        $script:SttUnpauseAt = (Get-Date).AddSeconds(6)
        $msg = if ($raw.message) { [string]$raw.message } else { 'Termine.' }
        if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 237) + '...' }
        $icon = if ($raw.ok) { 'Info' } else { 'Error' }
        Write-WatchLog ("AI prompt done ok={0}" -f [bool]$raw.ok)
        Show-Balloon -Title 'Fresh Agent IA' -Text $msg -Icon $icon
    }
    catch {
        Write-WatchLog ("AI poll: {0}" -f $_.Exception.Message)
    }
}

$script:FreshAgentRunAiTest = {
    # Pas de ShowDialog: la fenetre modale bloque le thread UI (RunTagged sans OK).
    Write-WatchLog 'AiTest enter'
    try {
        Start-FreshAgentAiPromptBackground -Prompt 'Reponds en une courte phrase: bonjour, je suis Fresh Agent.'
    }
    catch {
        Write-WatchLog ("AiTest error: {0}" -f $_.Exception.Message)
        Show-Balloon -Title 'Fresh Agent IA' -Text $_.Exception.Message -Icon Error
    }
    Write-WatchLog 'AiTest leave'
}
function Start-FreshAgentBackgroundWork {
    param(
        [ValidateSet('StartOllama', 'EnsureModel')]
        [string]$Action,
        [string]$BusyTitle = 'Fresh Agent',
        [string]$BusyText = 'Operation en cours...'
    )
    if (-not (Test-FreshAgentOllamaWorkerReady)) {
        Show-Balloon -Title $BusyTitle -Text 'Scripts Ollama absents (dossier ai\). Menu Fresh Windows → Mettre a jour scripts locaux.' -Icon Warning
        return
    }
    Show-Balloon -Title $BusyTitle -Text $BusyText -Icon Info
    $script:FaBgResultPending = $true
    $script:FaBgResultLastAt = $null
    $worker = Join-Path $script:FreshAppData 'ai\FreshAgent-BackgroundWorker.ps1'
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    Start-Process -FilePath $psExe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $worker,
        '-Action', $Action,
        '-FreshAppData', $script:FreshAppData,
        '-RepoRef', $script:RepoRef
    ) | Out-Null
    Start-FreshAgentBgPollTimerIfNeeded
}

function Start-FreshAgentBgPollTimerIfNeeded {
    if ($script:FaBgPollTimer) { return }
    try {
        $script:FaBgPollTimer = New-Object System.Windows.Forms.Timer
        $script:FaBgPollTimer.Interval = 1000
        $script:FaBgPollTimer.Add_Tick((Register-WatchUiHandler {
                try {
                    if ($script:WatchAgentSessionState) {
                        $null = $script:WatchAgentSessionState.InvokeCommand.InvokeScript(
                            $false, { Invoke-FreshAgentBackgroundResultPoll }, $null, @())
                    }
                    if (-not $script:FaBgResultPending -and $script:FaBgPollTimer) {
                        $script:FaBgPollTimer.Stop()
                        $script:FaBgPollTimer.Dispose()
                        $script:FaBgPollTimer = $null
                    }
                }
                catch { }
            }))
        $script:FaBgPollTimer.Start()
    }
    catch { }
}

function Invoke-FreshAgentBackgroundResultPoll {
    if (-not $script:FaBgResultPending) { return }
    $path = Join-Path $script:FreshAppData 'fa-bg-result.json'
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.at -and $raw.at -eq $script:FaBgResultLastAt) { return }
        $script:FaBgResultLastAt = [string]$raw.at
        $script:FaBgResultPending = $false
        $script:OllamaOkCacheAt = $null
        $msg = if ($raw.message) { [string]$raw.message } else { 'Operation terminee.' }
        $icon = if ($raw.ok) { 'Info' } else { 'Error' }
        Show-Balloon -Title 'Fresh Agent' -Text $msg -Icon $icon
        if ($raw.ok -and $raw.action -match 'Ollama|Model') {
            $script:OllamaOkCache = $true
            $script:OllamaOkCacheAt = Get-Date
        }
        if ($script:FreshAgentAiMenu) {
            $m = $script:FreshAgentAiMenu
            Update-FreshAgentAiMenu -MiAiRoot $m.Root -MiAiToggle $m.Toggle -MiOllamaState $m.OllamaState `
                -MiSttState $m.SttState -MiAiListen $m.Listen -MiTtsCycle $m.TtsCycle -MiRagToggle $m.RagToggle
        }
        if (Get-Command Update-FreshAgentDashboardIfOpen -ErrorAction SilentlyContinue) {
            Update-FreshAgentDashboardIfOpen
        }
    }
    catch {
        Write-WatchLog ("BgResult: {0}" -f $_.Exception.Message)
    }
}

function Start-FreshAgentQuickSpeak {
    param([Parameter(Mandatory)][string]$Text)
    $spoken = ($Text -replace '[^\p{L}\p{N}\s\.,!?''-]', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($spoken)) { return }
    if ($spoken.Length -gt 180) { $spoken = $spoken.Substring(0, 177) }
    $file = Join-Path $script:FreshAppData 'tts-say.txt'
    Set-Content -LiteralPath $file -Value $spoken -Encoding UTF8
    $tts = Join-Path $script:FreshAppData 'ai\FreshAgent-Tts.ps1'
    $cfgPath = Join-Path $script:FreshAppData 'configs\agent-ai.json'
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $cmd = @"
. '$($tts.Replace("'","''"))'
`$t = Get-Content -LiteralPath '$($file.Replace("'","''"))' -Raw -Encoding UTF8
`$cfg = `$null
try { `$cfg = Get-Content -LiteralPath '$($cfgPath.Replace("'","''"))' -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
if (-not (Invoke-FreshAgentSpeak -Text `$t -AiConfig `$cfg -FreshAppData '$($script:FreshAppData.Replace("'","''"))')) {
  Invoke-FreshAgentWindowsTts -Text `$t -AiConfig `$cfg | Out-Null
}
"@
    Start-Process -FilePath $psExe -WindowStyle Hidden -ArgumentList @('-NoProfile','-Command',$cmd) | Out-Null
}

$script:FreshAgentSttPoll = {
    if ($global:FreshAgentSttPaused -and -not $script:FaAiResultPending -and $script:SttUnpauseAt -and (Get-Date) -gt $script:SttUnpauseAt) {
        $global:FreshAgentSttPaused = $false
        Remove-Item -LiteralPath (Join-Path $script:FreshAppData 'fa-stt.paused') -Force -ErrorAction SilentlyContinue
        Write-WatchLog 'STT always-on resume'
    }
    $text = [string]$global:FreshAgentSttPending
    if ([string]::IsNullOrWhiteSpace($text)) {
        $pendingFile = Join-Path $script:FreshAppData 'fa-stt-pending.txt'
        if (Test-Path -LiteralPath $pendingFile) {
            $text = (Get-Content -LiteralPath $pendingFile -Raw -Encoding UTF8)
            Remove-Item -LiteralPath $pendingFile -Force -ErrorAction SilentlyContinue
        }
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $global:FreshAgentSttPending = $null
    $text = $text.Trim()
    Write-WatchLog ("STT entendu: {0}" -f $text)
    Show-FreshAgentUserNotice -Title 'Entendu' -Text $text -Level Info
    try {
        if ($script:FreshAgentDashboardUi -and $script:FreshAgentDashboardUi.LblStatus) {
            $script:FreshAgentDashboardUi.LblStatus.Text = ("Entendu: {0}" -f $text)
        }
    }
    catch { }

    # Router skills d'abord (sans Ollama)
    $routed = $false
    try {
        if (Get-Command Invoke-FreshAgentVoiceRouter -ErrorAction SilentlyContinue) {
            $r = Invoke-FreshAgentVoiceRouter -Transcript $text -FreshAppData $script:FreshAppData -RepoRef $script:RepoRef
            if ($r.matched) {
                $routed = $true
                Show-FreshAgentUserNotice -Title 'Skill' -Text ([string]$r.message) -Level $(if ($r.ok) { 'Info' } else { 'Warning' })
                if ($r.ok -and (Get-Command Start-FreshAgentQuickSpeak -ErrorAction SilentlyContinue)) {
                    Start-FreshAgentQuickSpeak -Text ([string]$r.message)
                }
            }
        }
    }
    catch {
        Write-WatchLog ("STT router: {0}" -f $_.Exception.Message)
    }

    if (-not $routed) {
        try {
            $cfg = Get-FreshAgentAiConfig -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData -PreferLocal
            if ($cfg.enabled) {
                Start-FreshAgentQuickSpeak -Text 'Je regarde.'
                Start-FreshAgentAiPromptBackground -Prompt $text
            }
            else {
                Show-FreshAgentUserNotice -Title 'Voix' -Text 'Commande non reconnue.' -Level Info
            }
        }
        catch {
            Write-WatchLog ("STT route: {0}" -f $_.Exception.Message)
        }
    }
}

function Start-FreshAgentSttPollTimerIfNeeded {
    if ($script:FaSttPollTimer) { return }
    $script:FaSttPollTimer = New-Object System.Windows.Forms.Timer
    $script:FaSttPollTimer.Interval = 400
    $script:FaSttPollTimer.Add_Tick((Register-WatchUiHandler {
            $poll = $script:FreshAgentSttPoll
            if ($poll -is [scriptblock]) { & $poll }
        }))
    $script:FaSttPollTimer.Start()
}

function Start-FreshAgentAlwaysOnVoice {
    # Legacy WhisperLoop retire. Voir Start-FreshAgentVoiceListenSession (voice_worker).
    if (Get-Command Start-FreshAgentVoiceListenSession -ErrorAction SilentlyContinue) {
        Start-FreshAgentVoiceListenSession
        return
    }
    Write-WatchLog 'STT: voice session unavailable (VoiceWorker not loaded)'
    Show-FreshAgentUserNotice -Title 'STT' -Text 'Ecoute vocale non prete (voice_worker).' -Level Warning
}

function Stop-FreshAgentAlwaysOnVoice {
    if (Get-Command Stop-FreshAgentVoiceListenSession -ErrorAction SilentlyContinue) {
        Stop-FreshAgentVoiceListenSession
        return
    }
    $script:VoiceAlwaysOn = $false
    $script:VoiceListenActive = $false
    $global:FreshAgentSttPaused = $true
    if ($script:WhisperLoopProc -and -not $script:WhisperLoopProc.HasExited) {
        try { Stop-Process -Id $script:WhisperLoopProc.Id -Force } catch { }
    }
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'FreshAgent-WhisperLoop' } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch { } }
    if (Get-Command Stop-WindowsSttAlwaysOn -ErrorAction SilentlyContinue) { Stop-WindowsSttAlwaysOn }
    if ($script:MiAiListenItem) { $script:MiAiListenItem.Text = 'Ecoute : OFF' }
    Write-WatchLog 'STT always-on stopped (legacy cleanup)'
}

function Invoke-FreshAgentVoiceListenMenu {
    if (-not $script:FreshAgentReady) {
        Show-FreshAgentUserNotice -Title 'STT' -Text 'Modules non charges.' -Level Warning
        return
    }
    if ($script:VoiceListenActive -or $script:VoiceAlwaysOn) {
        Stop-FreshAgentAlwaysOnVoice
        return
    }
    Start-FreshAgentAlwaysOnVoice
}

function Invoke-FreshAgentVoiceListenOn {
    if ($script:VoiceListenActive) { return }
    Start-FreshAgentAlwaysOnVoice
}

function Invoke-FreshAgentVoiceListenOff {
    if (-not $script:VoiceListenActive -and -not $script:VoiceAlwaysOn) { return }
    Stop-FreshAgentAlwaysOnVoice
}

function Show-FreshAgentUserNotice {
    param(
        [string]$Title = 'Fresh Agent',
        [string]$Text,
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    if (Get-Command Show-FreshAgentOverlay -ErrorAction SilentlyContinue) {
        Show-FreshAgentOverlay -Title $Title -Text $Text -Level $Level
        return
    }
    # Fallback discret: log seulement (plus de balloon invasif pour la voix/IA).
    Write-WatchLog ("notice [{0}] {1}: {2}" -f $Level, $Title, $Text)
}

function Invoke-FreshAgentTtsCycleMenu {
    if (-not $script:FreshAgentReady) { return }
    $cfg = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData -PreferLocal
    $cur = 'off'
    if (Get-Command Get-FreshAgentTtsProvider -ErrorAction SilentlyContinue) {
        $cur = Get-FreshAgentTtsProvider -AiConfig $cfg
    }
    $order = @('off', 'edge', 'windows', 'piper')
    $idx = [array]::IndexOf($order, $cur)
    if ($idx -lt 0) { $idx = 0 }
    $next = $order[($idx + 1) % $order.Count]
    Set-FreshAgentAiUserConfig -Patch @{ tts = @{ provider = $next } } -FreshAppData $FreshAppData
    $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData -PreferLocal
    Show-FreshAgentUserNotice -Title 'TTS' -Text ("TTS : {0}" -f $next.ToUpper()) -Level Info
    # Pas de Speak synchrone ici: ca bloque le thread UI WinForms.
}

function Invoke-FreshAgentAiHistoryMenu {
    if (-not (Get-Command Get-FreshAgentAiHistoryRecent -ErrorAction SilentlyContinue)) {
        Show-Balloon -Title 'Historique' -Text 'Module historique absent.' -Icon Warning
        return
    }
    $items = Get-FreshAgentAiHistoryRecent -Count 5 -FreshAppData $FreshAppData
    if (-not $items -or $items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Aucun echange IA enregistre.', 'Fresh Agent') | Out-Null
        return
    }
    $lines = @()
    foreach ($it in $items) {
        $p = [string]$it.prompt
        if ($p.Length -gt 80) { $p = $p.Substring(0, 77) + '...' }
        $lines += ("[{0}] {1}" -f $it.at, $p)
    }
    [System.Windows.Forms.MessageBox]::Show(($lines -join "`n"), 'Historique IA (5 derniers)') | Out-Null
}

function Update-FreshAgentAiMenu {
    param($MiAiRoot, $MiAiToggle, $MiOllamaState, $MiSttState, $MiAiListen, $MiTtsCycle, $MiRagToggle, [switch]$SkipNetworkChecks)
    if (-not $MiAiRoot) { return }
    $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData -PreferLocal
    $enabled = $false
    if ($script:FreshAgentAi -and $null -ne $script:FreshAgentAi.enabled) {
        $enabled = [bool]$script:FreshAgentAi.enabled
    }
    $MiAiToggle.Text = if ($enabled) { 'IA : ON' } else { 'IA : OFF (defaut)' }
    $ollamaOk = $false
    if (-not $SkipNetworkChecks -and (Get-Command Test-OllamaApi -ErrorAction SilentlyContinue)) {
        $base = if ($script:FreshAgentAi.ollama.baseUrl) { $script:FreshAgentAi.ollama.baseUrl } else { 'http://127.0.0.1:11434' }
        $ollamaOk = Test-OllamaApi -BaseUrl $base -TimeoutSec 1
        $script:OllamaOkCache = $ollamaOk
        $script:OllamaOkCacheAt = Get-Date
    }
    elseif ($script:OllamaOkCacheAt -and ((Get-Date) - [datetime]$script:OllamaOkCacheAt).TotalSeconds -lt 8) {
        $ollamaOk = [bool]$script:OllamaOkCache
    }
    $MiOllamaState.Text = if ($SkipNetworkChecks) { 'Ollama : (verification differee)' } elseif ($ollamaOk) { 'Ollama : actif' } else { 'Ollama : arrete / injoignable' }
    $sttMsg = 'STT : Windows API'
    if ($script:FreshAgentReady) { Ensure-FreshAgentSttLoaded | Out-Null }
    if (Get-Command Get-WindowsSttStatusMessage -ErrorAction SilentlyContinue) {
        try {
            $sttMsg = Get-WindowsSttStatusMessage -FreshAppData $FreshAppData -RepoRef $RepoRef
        }
        catch {
            $sttMsg = 'STT : (statut indisponible)'
        }
    }
    elseif (-not $script:FreshAgentReady) {
        $sttMsg = 'STT : modules en cours...'
    }
    if ($MiSttState) {
        $MiSttState.Text = $sttMsg
        $MiSttState.Enabled = [bool]$script:FreshAgentReady
    }
    if ($MiAiListen) {
        $listenOk = $false
        if (Get-Command Test-FreshAgentWindowsSttEnabled -ErrorAction SilentlyContinue) {
            try {
                $listenOk = [bool](Test-FreshAgentWindowsSttEnabled -AiConfig $script:FreshAgentAi)
            }
            catch {
                Write-WatchLog ("STT test: {0}" -f $_.Exception.Message)
            }
        }
        $prov = 'n/a'
        try {
            if ($script:FreshAgentAi -and $script:FreshAgentAi.stt) { $prov = [string]$script:FreshAgentAi.stt.provider }
        }
        catch { }
        # Apres boot: bouton actif pour pouvoir cliquer et recevoir un balloon explicite.
        $ready = [bool]$script:FreshAgentReady
        $MiAiListen.Enabled = $ready -and -not $script:VoiceListenActive
        $label = if ($listenOk) {
            'Ecouter (commande vocale Windows)'
        }
        elseif ($ready) {
            'Ecouter (STT indisponible — clic = detail)'
        }
        else {
            'Ecouter (modules...)'
        }
        $MiAiListen.Text = $label
        $script:MiAiListenLabel = $label
        $script:MiAiListenItem = $MiAiListen
        Write-WatchLog ("STT menu ready={0} listenOk={1} enabled={2} provider={3}" -f $ready, $listenOk, $MiAiListen.Enabled, $prov)
    }
    if ($MiTtsCycle -and (Get-Command Get-FreshAgentTtsProvider -ErrorAction SilentlyContinue)) {
        $p = Get-FreshAgentTtsProvider -AiConfig $script:FreshAgentAi
        $MiTtsCycle.Text = "TTS : $($p.ToUpper()) (clic = cycle)"
        $MiTtsCycle.Enabled = $true
    }
    if ($MiRagToggle) {
        $ragOn = $false
        if ($script:FreshAgentAi.rag -and $null -ne $script:FreshAgentAi.rag.enabled) {
            $ragOn = [bool]$script:FreshAgentAi.rag.enabled
        }
        $MiRagToggle.Text = if ($ragOn) { 'RAG guides : ON' } else { 'RAG guides : OFF' }
    }
    Update-FreshAgentTrayStatus
    if (Get-Command Update-FreshAgentDashboardIfOpen -ErrorAction SilentlyContinue) {
        Update-FreshAgentDashboardIfOpen
    }
}

function Import-FreshAgentDashboardAtScriptScope {
    if (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue) {
        return $true
    }
    $candidates = @(
        (Join-Path $script:FreshAppData 'lib\FreshAgent-Dashboard.ps1')
    )
    if ($PSScriptRoot) {
        $candidates += (Join-Path $PSScriptRoot 'lib\FreshAgent-Dashboard.ps1')
    }
    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            if (Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue) {
                if (Import-FreshAgentModule -RelativePath 'lib/FreshAgent-Dashboard.ps1' -FreshAppData $script:FreshAppData) {
                    return $true
                }
            }
            $escaped = $path.Replace("'", "''")
            $dot = [scriptblock]::Create(". '$escaped'")
            $null = $ExecutionContext.InvokeCommand.InvokeScript($false, $dot, $null, @())
            if (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue) {
                return $true
            }
        }
        catch {
            Write-WatchLog ("Dashboard dot-source: {0}" -f $_.Exception.Message)
        }
    }
    if (Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue) {
        Import-FreshAgentModule -RelativePath 'lib/FreshAgent-Dashboard.ps1' -FreshAppData $script:FreshAppData | Out-Null
    }
    return [bool](Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)
}

function Ensure-FreshAgentDashboardLoaded {
    Import-FreshAgentDashboardAtScriptScope
}

function Test-FreshAgentAiBridgeReady {
    if (-not $script:FreshAgentReady) {
        Show-Balloon -Title 'IA' -Text 'Modules non charges.' -Icon Warning
        return $false
    }
    # Check rapide fichiers + commande (pas de re-import synchrone qui bloque l UI).
    if (Get-Command Invoke-FreshAgentAiTurn -ErrorAction SilentlyContinue) {
        return $true
    }
    $missing = @()
    foreach ($rel in @(
            'lib\FreshAgent-SkillsEngine.ps1',
            'ai\Ollama-Manager.ps1',
            'ai\FreshAgent-OllamaBridge.ps1'
        )) {
        if (-not (Test-Path -LiteralPath (Join-Path $script:FreshAppData $rel))) {
            $missing += $rel
        }
    }
    if ($missing.Count -eq 0) {
        try {
            if (Get-Command Ensure-FreshAgentAiBridgeLoaded -ErrorAction SilentlyContinue) {
                Ensure-FreshAgentAiBridgeLoaded -FreshAppData $script:FreshAppData | Out-Null
            }
        }
        catch {
            Write-WatchLog ("AiBridge load: {0}" -f $_.Exception.Message)
        }
        if (Get-Command Invoke-FreshAgentAiTurn -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    $detail = if ($missing.Count -gt 0) { "Fichiers manquants: $($missing -join ', ')" } else { 'Sync scripts locaux puis redemarrer l agent.' }
    Show-Balloon -Title 'IA' -Text "Bridge Ollama absent — $detail" -Icon Warning
    return $false
}

function Get-FreshAgentDashboardState {
    $st = Get-WatchUserSettings
    $aiOn = $false
    $ragOn = $false
    $ollamaOk = $false
    $sttMsg = 'STT : —'
    $listenOk = $false
    $listenOffOk = $false
    $aiControls = $false
    $aiNotice = 'Voix / IA : chantier en reconstruction. Core mode jeu et skills restent actifs.'
    if ($script:FreshAgentReady) {
        $cfg = $script:FreshAgentAi
        if (-not $cfg -and (Get-Command Get-FreshAgentAiConfig -ErrorAction SilentlyContinue)) {
            try {
                $cfg = Get-FreshAgentAiConfig -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData -PreferLocal
                $script:FreshAgentAi = $cfg
            }
            catch { }
        }
        if ($cfg) {
            if ($null -ne $cfg.enabled) { $aiOn = [bool]$cfg.enabled }
            if ($cfg.rag -and $null -ne $cfg.rag.enabled) { $ragOn = [bool]$cfg.rag.enabled }
        }
        $base = 'http://127.0.0.1:11434'
        try {
            if ($cfg -and $cfg.ollama -and $cfg.ollama.baseUrl) {
                $base = [string]$cfg.ollama.baseUrl
            }
        }
        catch { }
        $cacheOk = $false
        try {
            if ($script:OllamaOkCacheAt -and ((Get-Date) - [datetime]$script:OllamaOkCacheAt).TotalSeconds -lt 8) {
                $ollamaOk = [bool]$script:OllamaOkCache
                $cacheOk = $true
            }
        }
        catch { }
        if (-not $cacheOk) {
            try {
                if (Get-Command Test-OllamaApi -ErrorAction SilentlyContinue) {
                    $ollamaOk = [bool](Test-OllamaApi -BaseUrl $base -TimeoutSec 1)
                }
                else {
                    $uri = ($base.Trim().TrimEnd('/') + '/api/tags') -replace '(?i)^(https?://)localhost', '${1}127.0.0.1'
                    $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 1
                    $ollamaOk = ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
                }
            }
            catch {
                $ollamaOk = $false
            }
            $script:OllamaOkCache = $ollamaOk
            $script:OllamaOkCacheAt = Get-Date
        }
        if (Get-Command Get-WindowsSttStatusMessage -ErrorAction SilentlyContinue) {
            try {
                $sttMsg = Get-WindowsSttStatusMessage -FreshAppData $script:FreshAppData -RepoRef $script:RepoRef
            }
            catch { }
        }
        if (Get-Command Test-FreshAgentWindowsSttEnabled -ErrorAction SilentlyContinue) {
            try {
                $null = Test-FreshAgentWindowsSttEnabled -AiConfig $cfg
            }
            catch { }
        }
        # Ecoute ON si modules prets et session inactive (telecharge worker au premier ON).
        $listenOk = [bool]$script:FreshAgentReady -and -not $script:VoiceListenActive -and `
            [bool](Get-Command Start-FreshAgentVoiceListenSession -ErrorAction SilentlyContinue)
        $listenOffOk = [bool]$script:VoiceListenActive
        $aiControls = [bool]$script:FreshAgentReady
        $aiNotice = 'Voix OFF par defaut. Ecoute ON demarre voice_worker (asset local).'
        if ($script:VoiceListenActive) {
            $aiNotice = 'Ecoute active — parlez pour une commande PC.'
        }
        elseif ($cfg -and $cfg.voice -and [bool]$cfg.voice.enabled) {
            $aiNotice = 'Voix habilitee — utilisez Ecoute ON / OFF.'
        }
        if (Get-Command Get-FreshAgentVoiceStatusMessage -ErrorAction SilentlyContinue) {
            try { $sttMsg = Get-FreshAgentVoiceStatusMessage -FreshAppData $script:FreshAppData -AiConfig $cfg } catch { }
        }
    }
    $summary = if ($script:NotifyIcon) { $script:NotifyIcon.Text } else { 'Fresh Agent' }
    return @{
        AutoSuggestKill   = [bool]$st.autoSuggestKill
        MonitorEnabled    = [bool]$st.monitorEnabled
        AiEnabled         = $aiOn
        RagEnabled        = $ragOn
        OllamaOk          = $ollamaOk
        SttMessage        = $sttMsg
        ListenEnabled     = $listenOk
        ListenOffEnabled  = $listenOffOk
        ListenButtonText  = if ($script:VoiceListenActive) { 'Ecoute active…' } else { 'Ecoute ON' }
        AiControlsEnabled = $aiControls
        AiNotice          = $aiNotice
        FreshAgentReady   = [bool]$script:FreshAgentReady
        TraySummary       = $summary
    }
}

function Invoke-FreshAgentSttStatusMenu {
    if (-not $script:FreshAgentReady) {
        Show-Balloon -Title 'STT' -Text 'Modules non charges.' -Icon Warning
        return
    }
    $msg = 'STT : ?'
    if (Get-Command Get-WindowsSttStatusMessage -ErrorAction SilentlyContinue) {
        try {
            $msg = Get-WindowsSttStatusMessage -FreshAppData $FreshAppData -RepoRef $RepoRef
        }
        catch {
            $msg = $_.Exception.Message
        }
    }
    else {
        $msg = 'Module Windows-Stt absent — sync scripts locaux.'
    }
    Show-Balloon -Title 'STT' -Text $msg -Icon Info
}

function Set-FreshAgentAiEnabledFromUi {
    param([bool]$Enabled)
    if (-not $script:FreshAgentReady) {
        Show-Balloon -Title 'IA' -Text 'Modules non charges.' -Icon Warning
        return
    }
    Set-FreshAgentAiUserConfig -Patch @{ enabled = $Enabled } -FreshAppData $script:FreshAppData
    $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData -PreferLocal
    if ($script:FreshAgentAiMenu) {
        $m = $script:FreshAgentAiMenu
        Update-FreshAgentAiMenu -MiAiRoot $m.Root -MiAiToggle $m.Toggle -MiOllamaState $m.OllamaState `
            -MiSttState $m.SttState -MiAiListen $m.Listen -MiTtsCycle $m.TtsCycle -MiRagToggle $m.RagToggle
    }
    if ($Enabled -and $script:FreshAgentAi.ollama.autoStart) {
        Start-FreshAgentBackgroundWork -Action EnsureModel -BusyText 'Demarrage Ollama + modele...'
    }
    Update-FreshAgentDashboardIfOpen
}

function Set-FreshAgentRagEnabledFromUi {
    param([bool]$Enabled)
    if (-not $script:FreshAgentReady) { return }
    Set-FreshAgentAiUserConfig -Patch @{ rag = @{ enabled = $Enabled } } -FreshAppData $script:FreshAppData
    $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData -PreferLocal
    if ($Enabled -and (Get-Command Build-FreshAgentRagIndex -ErrorAction SilentlyContinue)) {
        try { Build-FreshAgentRagIndex -RepoRef $script:RepoRef -FreshAppData $script:FreshAppData | Out-Null } catch { }
    }
    if ($script:FreshAgentAiMenu) {
        $m = $script:FreshAgentAiMenu
        Update-FreshAgentAiMenu -MiAiRoot $m.Root -MiAiToggle $m.Toggle -MiOllamaState $m.OllamaState `
            -MiSttState $m.SttState -MiAiListen $m.Listen -MiTtsCycle $m.TtsCycle -MiRagToggle $m.RagToggle
    }
    Update-FreshAgentDashboardIfOpen
}

function Open-FreshAgentDashboardPanel {
    if ($script:FreshAgentDashboardOpening) {
        Write-WatchLog 'Dashboard open ignore (deja en cours)'
        return
    }
    $script:FreshAgentDashboardOpening = $true
    try {
    $dashPath = Join-Path $script:FreshAppData 'lib\FreshAgent-Dashboard.ps1'
    if (-not (Test-Path -LiteralPath $dashPath)) {
        Write-WatchLog ("Dashboard fichier absent: {0}" -f $dashPath)
        Show-Balloon -Title 'Fresh Agent' -Text 'Panneau absent — sync scripts locaux (lib\FreshAgent-Dashboard.ps1) puis redemarrer l agent.' -Icon Warning
        return
    }
    try {
        $dashAge = (Get-Item -LiteralPath $dashPath).LastWriteTimeUtc.ToString('o')
        Write-WatchLog ("Dashboard open: {0} (mtime UTC {1})" -f $dashPath, $dashAge)
        Set-WatchScriptUtf8Bom -Path $dashPath
    }
    catch { }

    try {
    # Rebuild action map each open (evite closures / code obsolete en memoire).
    $script:FreshAgentDashboardActionMap = @{
            ToggleAutoSuggest = {
                param([bool]$On)
                $s = Get-WatchUserSettings
                $s.autoSuggestKill = $On
                Set-WatchUserSettings -Settings $s
                $script:UserSettings = $s
                if ($script:WatchMenuAutoItem) {
                    $script:WatchMenuAutoItem.Text = if ($On) { 'Detection auto : ON' } else { 'Detection auto : OFF' }
                }
            }
            ToggleMonitor     = {
                param([bool]$On)
                $s = Get-WatchUserSettings
                $s.monitorEnabled = $On
                Set-WatchUserSettings -Settings $s
                $script:UserSettings = $s
                if ($script:WatchMenuMonItem) {
                    $script:WatchMenuMonItem.Text = if ($On) { 'Surveillance : ON' } else { 'Surveillance : OFF' }
                }
            }
            GameModeKill      = { Invoke-GameModeKillNow }
            IdleLaunchers     = { Invoke-IdleLaunchersOnly }
            PendingKill       = { Stop-PendingSuggestedProcesses }
            ProfileGame       = { & $script:FreshAgentStartProfileBg 'game' }
            ProfileWork       = { & $script:FreshAgentStartProfileBg 'work' }
            ProfileClean      = { & $script:FreshAgentStartProfileBg 'clean' }
            SkillHealth       = { & $script:FreshAgentStartSkillBg 'check_system_health' @{} }
            SkillGameSession  = { & $script:FreshAgentStartSkillBg 'game_session' @{} }
            SkillEndGame      = { & $script:FreshAgentStartSkillBg 'end_game_session' @{} }
            SetAiEnabled      = { param([bool]$On) Set-FreshAgentAiEnabledFromUi -Enabled $On }
            SetRagEnabled     = { param([bool]$On) Set-FreshAgentRagEnabledFromUi -Enabled $On }
            StartOllama       = { Start-FreshAgentBackgroundWork -Action StartOllama -BusyText 'Demarrage Ollama...' }
            EnsureModel       = { Start-FreshAgentBackgroundWork -Action EnsureModel -BusyText 'Telechargement modele...' }
            VoiceListen       = { Invoke-FreshAgentVoiceListenMenu }
            VoiceListenOn     = { Invoke-FreshAgentVoiceListenOn }
            VoiceListenOff    = { Invoke-FreshAgentVoiceListenOff }
            TtsCycle          = { Invoke-FreshAgentTtsCycleMenu }
            AiTest            = {
                $run = $script:FreshAgentRunAiTest
                if ($run -is [scriptblock]) { & $run }
            }
            AiHistory         = { Invoke-FreshAgentAiHistoryMenu }
            FwMenu            = { try { Start-FreshWindowsElevated -RepoRef $script:RepoRef } catch { Show-FreshAgentUserNotice -Title 'Fresh Windows' -Text $_.Exception.Message -Level Error } }
            FwMaintenance     = { try { Start-FreshWindowsElevated -SilentMode 'maintenance' -RepoRef $script:RepoRef } catch { Show-FreshAgentUserNotice -Title 'Fresh Windows' -Text $_.Exception.Message -Level Error } }
            FwGameMode        = { try { Start-FreshWindowsElevated -SilentMode 'game-mode' -RepoRef $script:RepoRef } catch { Show-FreshAgentUserNotice -Title 'Fresh Windows' -Text $_.Exception.Message -Level Error } }
            SyncScripts       = { Invoke-SyncLocalScripts }
            OpenPowerShell    = { try { Start-FreshWindowsPowerShell } catch { Show-FreshAgentUserNotice -Title 'PowerShell' -Text $_.Exception.Message -Level Error } }
            QuitAgent         = { Request-WatchAgentShutdown }
        }
        $getState = (Get-Command Get-FreshAgentDashboardState -CommandType Function -ErrorAction Stop).ScriptBlock
        $escapedDash = $dashPath.Replace("'", "''")
        $runner = [scriptblock]::Create(@"
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    . '$escapedDash'
}
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    throw 'Show-FreshAgentDashboard absent apres chargement dashboard'
}
if (-not `$script:FreshAgentDashboardActionMap) {
    throw 'FreshAgentDashboardActionMap absent'
}
`$st = (Get-Command Get-FreshAgentDashboardState -CommandType Function -ErrorAction Stop).ScriptBlock
Show-FreshAgentDashboard -Actions `$script:FreshAgentDashboardActionMap -GetState `$st
"@)
        if ($script:WatchAgentSessionState) {
            $null = $script:WatchAgentSessionState.InvokeCommand.InvokeScript($false, $runner, $null, @())
        }
        else {
            . $dashPath
            Show-FreshAgentDashboard -Actions $script:FreshAgentDashboardActionMap -GetState $getState
        }
    }
    catch {
        Write-WatchLog ("Dashboard open: {0}" -f $_.Exception.ToString())
        Show-Balloon -Title 'Fresh Agent' -Text $_.Exception.Message -Icon Error
    }
    }
    finally {
        $script:FreshAgentDashboardOpening = $false
    }
}

function Invoke-SyncLocalScripts {
    try {
        $syncScript = Join-Path $FreshAppData 'Sync-FreshWindowsAgent.ps1'
        if (-not (Test-Path -LiteralPath $syncScript)) {
            $url = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/scripts/Sync-FreshWindowsAgent.ps1"
            Invoke-WebRequest -Uri $url -OutFile $syncScript -UseBasicParsing
            Write-WatchLog 'Sync-FreshWindowsAgent.ps1 telecharge'
        }
        if (Test-Path -LiteralPath $syncScript) {
            & $psExe -NoProfile -ExecutionPolicy Bypass -File $syncScript -RepoRef $RepoRef
            Show-Balloon -Title 'Scripts locaux' -Text "Sync Fresh Agent OK (ref $RepoRef)." -Icon Info
            return
        }
        $corePath = Join-Path $FreshAppData 'Launcher-Core.ps1'
        $coreUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/scripts/lib/Launcher-Core.ps1"
        Invoke-WebRequest -Uri $coreUrl -OutFile $corePath -UseBasicParsing
        Set-Content -LiteralPath (Join-Path $FreshAppData 'Launcher-Core.ps1.ref') -Value $RepoRef -Encoding UTF8 -NoNewline
        . $corePath
        $launcherUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/launcher.ps1"
        $iconUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/assets/fresh-windows.ico"
        Write-FreshWindowsLaunchStub -FreshAppData $FreshAppData -Ref $RepoRef -LauncherUrl $launcherUrl | Out-Null
        Sync-GameModeLocalScripts -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $RepoRef -IconUrl $iconUrl | Out-Null
        if (Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue) {
            foreach ($mod in @(
                    'lib/FreshAgent-SkillsEngine.ps1',
                    'lib/FreshAgent-SkillHandlers.ps1',
                    'lib/FreshAgent-GameSession.ps1',
                    'ai/Ollama-Manager.ps1',
                    'ai/FreshAgent-OllamaBridge.ps1',
                    'ai/Windows-Stt.ps1',
                    'ai/FreshAgent-Tts.ps1',
                    'lib/FreshAgent-Inventory.ps1',
                    'lib/FreshAgent-Rag.ps1',
                    'lib/FreshAgent-History.ps1',
                    'lib/FreshAgent-Profiles.ps1',
                    'lib/FreshAgent-Log.ps1',
                    'lib/FreshAgent-Dashboard.ps1'
                )) {
                    Import-FreshAgentModule -RelativePath $mod -FreshAppData $FreshAppData | Out-Null
                }
            $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
            $script:FreshAgentReady = $true
        }
        Import-FreshAgentDashboardAtScriptScope | Out-Null
        if (Get-Command Ensure-FreshAgentAiBridgeLoaded -ErrorAction SilentlyContinue) {
            Ensure-FreshAgentAiBridgeLoaded -FreshAppData $FreshAppData | Out-Null
        }
        if (Get-Command Write-FreshAgentLog -ErrorAction SilentlyContinue) {
            Write-FreshAgentLog -Category 'Sync' -Message "Menu sync OK ref=$RepoRef" -FreshAppData $FreshAppData
        }
        Show-Balloon -Title 'Scripts locaux' -Text "Mis a jour (ref $RepoRef). Modules Fresh Agent recharges." -Icon Info
    }
    catch {
        Show-Balloon -Title 'Scripts locaux' -Text $_.Exception.Message -Icon Error
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

function Install-WatchAgentFullTrayMenu {
    if ($script:WatchFullMenuInstalled) { return }
    Write-WatchLog 'Init UI (menu complet)'
    Update-FreshAgentTrayStatus

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

$miOpenPanel = New-Object System.Windows.Forms.ToolStripMenuItem
$miOpenPanel.Text = 'Ouvrir le panneau Fresh Agent...'
$miOpenPanel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$null = $menu.Items.Add($miOpenPanel)
Add-WatchMenuClick $miOpenPanel { Open-FreshAgentDashboardPanel }
$menu.Items.Add('-') | Out-Null

$miKill = $menu.Items.Add('Mode jeu (liste + launchers inactifs)')
Add-WatchMenuClick $miKill { Invoke-GameModeKillNow }

$miLaunchers = $menu.Items.Add('Fermer launchers gaming inactifs')
Add-WatchMenuClick $miLaunchers { Invoke-IdleLaunchersOnly }

$miPending = $menu.Items.Add('Tuer suggestions en attente')
Add-WatchMenuClick $miPending { Stop-PendingSuggestedProcesses }

$miAuto = $menu.Items.Add('Détection auto : ON')
$script:WatchMenuAutoItem = $miAuto
Add-WatchMenuClick $miAuto {
    $s = Get-WatchUserSettings
    $s.autoSuggestKill = -not $s.autoSuggestKill
    Set-WatchUserSettings -Settings $s
    $script:UserSettings = $s
    $miAuto.Text = if ($s.autoSuggestKill) { 'Détection auto : ON' } else { 'Détection auto : OFF' }
}

$miMon = $menu.Items.Add('Surveillance : ON')
$script:WatchMenuMonItem = $miMon
Add-WatchMenuClick $miMon {
    $s = Get-WatchUserSettings
    $s.monitorEnabled = -not $s.monitorEnabled
    Set-WatchUserSettings -Settings $s
    $script:UserSettings = $s
    $miMon.Text = if ($s.monitorEnabled) { 'Surveillance : ON' } else { 'Surveillance : OFF' }
}

$menu.Items.Add('-') | Out-Null

$miSkillHealth = $menu.Items.Add('Etat systeme (skill)')
Add-WatchMenuClick $miSkillHealth { Invoke-FreshAgentSkillMenu -SkillId 'check_system_health' }

$miSkillGame = $menu.Items.Add('Session jeu (DND + mode jeu)')
Add-WatchMenuClick $miSkillGame { Invoke-FreshAgentSkillMenu -SkillId 'game_session' }

$miSkillEndGame = $menu.Items.Add('Fin session jeu')
Add-WatchMenuClick $miSkillEndGame { Invoke-FreshAgentSkillMenu -SkillId 'end_game_session' }

$miProfiles = New-Object System.Windows.Forms.ToolStripMenuItem
$miProfiles.Text = 'Profils'
$null = $menu.Items.Add($miProfiles)
foreach ($pair in @(
        @{ Id = 'game'; Label = 'Jeu (session)' },
        @{ Id = 'work'; Label = 'Travail (fin session + sante)' },
        @{ Id = 'clean'; Label = 'Clean (sante + inventaire)' }
    )) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $pair.Label
    $item.Tag = $pair.Id
    Add-WatchMenuClick $item {
            param($sender, $e)
            $run = $script:FreshAgentStartProfileBg
            if ($run -is [scriptblock]) {
                & $run ([string]$sender.Tag)
            }
            else {
                Invoke-FreshAgentProfileFromUi -ProfileId ([string]$sender.Tag)
            }
        }
    $miProfiles.DropDownItems.Add($item) | Out-Null
}

$menu.Items.Add('-') | Out-Null

$miAi = New-Object System.Windows.Forms.ToolStripMenuItem
$miAi.Text = 'Intelligence artificielle'
$null = $menu.Items.Add($miAi)

$miAiToggle = New-Object System.Windows.Forms.ToolStripMenuItem
$miAiToggle.Text = 'IA : OFF (defaut)'
Add-WatchMenuClick $miAiToggle {
    if (-not $script:FreshAgentReady) {
        Show-Balloon -Title 'IA' -Text 'Modules non charges.' -Icon Warning
        return
    }
    $cur = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
    $next = -not [bool]$cur.enabled
    Set-FreshAgentAiUserConfig -Patch @{ enabled = $next } -FreshAppData $FreshAppData
    $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
    Update-FreshAgentAiMenu -MiAiRoot $miAi -MiAiToggle $miAiToggle -MiOllamaState $miOllamaState -MiSttState $miSttState -MiAiListen $miAiListen -MiTtsCycle $miTtsCycle -MiRagToggle $miRagToggle
    if ($next -and $script:FreshAgentAi.ollama.autoStart) {
        Start-FreshAgentBackgroundWork -Action EnsureModel -BusyText 'Demarrage Ollama + modele...'
    }
}
$miAi.DropDownItems.Add($miAiToggle) | Out-Null

$miOllamaStart = New-Object System.Windows.Forms.ToolStripMenuItem
$miOllamaStart.Text = 'Demarrer Ollama'
Add-WatchMenuClick $miOllamaStart {
    Start-FreshAgentBackgroundWork -Action StartOllama -BusyText 'Demarrage Ollama...'
}
$miAi.DropDownItems.Add($miOllamaStart) | Out-Null

$miOllamaPull = New-Object System.Windows.Forms.ToolStripMenuItem
$miOllamaPull.Text = 'Telecharger modele par defaut'
Add-WatchMenuClick $miOllamaPull {
    Start-FreshAgentBackgroundWork -Action EnsureModel -BusyText 'Telechargement modele...'
}
$miAi.DropDownItems.Add($miOllamaPull) | Out-Null

$miOllamaState = New-Object System.Windows.Forms.ToolStripMenuItem
$miOllamaState.Text = 'Ollama : ?'
$miOllamaState.Enabled = $false
$miAi.DropDownItems.Add($miOllamaState) | Out-Null

$miSttState = New-Object System.Windows.Forms.ToolStripMenuItem
$miSttState.Text = 'STT : Windows API'
$miSttState.Enabled = $false
Add-WatchMenuClick $miSttState { Invoke-FreshAgentSttStatusMenu }
$miAi.DropDownItems.Add($miSttState) | Out-Null

$miAiListen = New-Object System.Windows.Forms.ToolStripMenuItem
$miAiListen.Text = 'Ecoute : OFF'
$miAiListen.Enabled = $false
Add-WatchMenuClick $miAiListen { Invoke-FreshAgentVoiceListenMenu }
$miAi.DropDownItems.Add($miAiListen) | Out-Null

$miTtsCycle = New-Object System.Windows.Forms.ToolStripMenuItem
$miTtsCycle.Text = 'TTS : OFF (clic = cycle)'
Add-WatchMenuClick $miTtsCycle { Invoke-FreshAgentTtsCycleMenu }
$miAi.DropDownItems.Add($miTtsCycle) | Out-Null

$miRagToggle = New-Object System.Windows.Forms.ToolStripMenuItem
$miRagToggle.Text = 'RAG guides : OFF'
Add-WatchMenuClick $miRagToggle {
    if (-not $script:FreshAgentReady) { return }
    $cur = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
    $ragOn = -not [bool]$cur.rag.enabled
    Set-FreshAgentAiUserConfig -Patch @{ rag = @{ enabled = $ragOn } } -FreshAppData $FreshAppData
    $script:FreshAgentAi = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
    if ($ragOn -and (Get-Command Build-FreshAgentRagIndex -ErrorAction SilentlyContinue)) {
        try { Build-FreshAgentRagIndex -RepoRef $RepoRef -FreshAppData $FreshAppData | Out-Null } catch { }
    }
    Update-FreshAgentAiMenu -MiAiRoot $miAi -MiAiToggle $miAiToggle -MiOllamaState $miOllamaState -MiSttState $miSttState -MiAiListen $miAiListen -MiTtsCycle $miTtsCycle -MiRagToggle $miRagToggle
}
$miAi.DropDownItems.Add($miRagToggle) | Out-Null

$miAiHistory = New-Object System.Windows.Forms.ToolStripMenuItem
$miAiHistory.Text = 'Historique IA (5 derniers)'
Add-WatchMenuClick $miAiHistory { Invoke-FreshAgentAiHistoryMenu }
$miAi.DropDownItems.Add($miAiHistory) | Out-Null

$miAiTest = New-Object System.Windows.Forms.ToolStripMenuItem
$miAiTest.Text = 'Tester l IA (tool calling)...'
Add-WatchMenuClick $miAiTest {
    $run = $script:FreshAgentRunAiTest
    if ($run -is [scriptblock]) { & $run }
}
$miAi.DropDownItems.Add($miAiTest) | Out-Null

$script:FreshAgentAiMenu = @{
    Root        = $miAi
    Toggle      = $miAiToggle
    OllamaState = $miOllamaState
    SttState    = $miSttState
    Listen      = $miAiListen
    TtsCycle    = $miTtsCycle
    RagToggle   = $miRagToggle
}
if ($script:FreshAgentReady) {
    Update-FreshAgentAiMenu -MiAiRoot $miAi -MiAiToggle $miAiToggle -MiOllamaState $miOllamaState -MiSttState $miSttState -MiAiListen $miAiListen -MiTtsCycle $miTtsCycle -MiRagToggle $miRagToggle
}
else {
    $miAi.Enabled = $false
}

$menu.Items.Add('-') | Out-Null

$miFw = New-Object System.Windows.Forms.ToolStripMenuItem
$miFw.Text = 'Fresh Windows (terminal admin)'
$null = $menu.Items.Add($miFw)

$miFwMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$miFwMenu.Text = 'Menu interactif (comme le raccourci Bureau)'
Add-WatchMenuClick $miFwMenu {
    try { Start-FreshWindowsElevated -RepoRef $RepoRef } catch { Show-Balloon -Title 'Fresh Windows' -Text $_.Exception.Message -Icon Error }
}
$miFw.DropDownItems.Add($miFwMenu)

$fwModes = @(
    @{ Label = 'Maintenance (WinUtil + ShutUp10)'; Mode = 'maintenance' },
    @{ Label = 'WinUtil one-click'; Mode = 'winutil-oneclick' },
    @{ Label = 'Winget upgrade --all'; Mode = 'winget-upgrade' },
    @{ Label = 'Mode jeu (via launcher admin)'; Mode = 'game-mode' }
)
foreach ($pair in $fwModes) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $pair.Label
    $item.Tag = $pair.Mode
    Add-WatchMenuClick $item {
        param($sender, $e)
        $m = $sender.Tag
        try { Start-FreshWindowsElevated -SilentMode $m -RepoRef $RepoRef } catch { Show-Balloon -Title 'Fresh Windows' -Text $_.Exception.Message -Icon Error }
    }
    $miFw.DropDownItems.Add($item) | Out-Null
}

$miPs = New-Object System.Windows.Forms.ToolStripMenuItem
$miPs.Text = 'Ouvrir PowerShell (sans admin)'
Add-WatchMenuClick $miPs {
    try {
        Start-FreshWindowsPowerShell
    }
    catch {
        Show-Balloon -Title 'PowerShell' -Text $_.Exception.Message -Icon Error
    }
}
$miFw.DropDownItems.Add($miPs) | Out-Null

$miSync = New-Object System.Windows.Forms.ToolStripMenuItem
$miSync.Text = 'Mettre à jour scripts locaux (ref GitHub)'
Add-WatchMenuClick $miSync { Invoke-SyncLocalScripts }
$miFw.DropDownItems.Add($miSync) | Out-Null

$menu.Items.Add('-') | Out-Null
$miExit = $menu.Items.Add('Quitter')
Add-WatchMenuClick $miExit { Request-WatchAgentShutdown }

    $script:WatchContextMenuStrip = $menu
    Set-WatchAgentNotifyIconInteractive

    if ($script:WatchMenuAutoItem) {
        $script:WatchMenuAutoItem.Text = if ($script:UserSettings.autoSuggestKill) { 'Détection auto : ON' } else { 'Détection auto : OFF' }
    }
    if ($script:WatchMenuMonItem) {
        $script:WatchMenuMonItem.Text = if ($script:UserSettings.monitorEnabled) { 'Surveillance : ON' } else { 'Surveillance : OFF' }
    }
    $script:WatchFullMenuInstalled = $true
    Write-WatchLog 'Menu complet installe'
}

function Start-WatchAgentPollTimerIfNeeded {
    if ($script:WatchPollTimer) { return }
    $pollMs = [math]::Max(5000, [int]$script:WatchRules.pollIntervalSeconds * 1000)
    $script:WatchPollTimer = New-Object System.Windows.Forms.Timer
    $script:WatchPollTimer.Interval = $pollMs
    $script:WatchPollTimer.Add_Tick((Register-WatchUiHandler { Invoke-WatchTick }))
    $script:WatchPollTimer.Start()
    Write-WatchLog 'Surveillance poll demarree (post-boot modules)'
}

function Start-WatchAgentTimers {
    if ($script:WatchBootTimer) { return }
    $script:WatchBootTimer = New-Object System.Windows.Forms.Timer
    $script:WatchBootTimer.Interval = 400
    $script:WatchBootTimer.Add_Tick((Register-WatchUiHandler {
            $script:WatchBootTimer.Stop()
            $script:WatchBootTimer.Dispose()
            $script:WatchBootTimer = $null
            Invoke-FreshAgentDeferredBoot
        }))
    $script:WatchBootTimer.Start()

    if (-not $script:WatchModuleDelayTimer) {
        $script:WatchModuleDelayTimer = New-Object System.Windows.Forms.Timer
        $script:WatchModuleDelayTimer.Interval = 5000
        $script:WatchModuleDelayTimer.Add_Tick((Register-WatchUiHandler {
                $script:WatchModuleDelayTimer.Stop()
                $script:WatchModuleDelayTimer.Dispose()
                $script:WatchModuleDelayTimer = $null
                Write-WatchLog 'Demarrage boot modules (apres delai UI)'
                Start-WatchAgentModuleBootAsync
            }))
        $script:WatchModuleDelayTimer.Start()
        Write-WatchLog 'Boot modules planifie (+5s, UI prioritaire)'
    }
}

function Start-WatchAgentUiBootstrap {
    if ($script:WatchUiBootstrapStarted) { return }
    $script:WatchUiBootstrapStarted = $true
    try {
        Install-WatchAgentFullTrayMenu
        Start-WatchAgentTimers
        Refresh-WatchAgentTrayVisibility
        if (Get-Command Show-FreshAgentOverlay -ErrorAction SilentlyContinue) {
            Show-FreshAgentOverlay -Title 'Fresh Agent' -Text 'Actif — icone dans la zone de notification (chevron ^ si masquee).' -Level Info -FadeMs 6000
        }
        else {
            Show-Balloon -Title 'Fresh Agent' -Text 'Agent actif — regardez la zone de notification (icones cachees ^).' -Icon Info
        }
        Write-WatchLog 'UI bootstrap OK'
    }
    catch {
        Write-WatchLog ("UI bootstrap: {0}" -f $_.Exception.Message)
    }
}

# --- UI (formulaire cache obligatoire pour le message loop WinForms) ---
$ErrorActionPreference = 'Continue'
$script:WatchAgentExitRequested = $false
$script:WatchAgentInMessageLoop = $false
if (-not (Test-WatchAgentSystrayLive)) {
    Initialize-WatchAgentSystrayEarly
}
if ($script:WatchAgentExitRequested) {
    Write-WatchLog 'Sortie demandee avant message loop'
    exit 0
}
if (-not (Test-WatchAgentSystrayLive)) {
    Write-WatchLog 'UI systray indisponible — abandon Run'
    exit 1
}
$script:WatchFullMenuInstalled = $false

$script:WatchBootstrapTimer = New-Object System.Windows.Forms.Timer
$script:WatchBootstrapTimer.Interval = 150
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
$script:WatchAgentInMessageLoop = $true
try {
    [System.Windows.Forms.Application]::Run($script:HiddenForm)
}
catch {
    Write-WatchLog ("Run: {0}" -f $_.Exception.Message)
    try {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Fresh Windows agent')
    } catch { }
    throw
}
