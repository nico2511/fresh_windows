#Requires -Version 5.1
<#
.SYNOPSIS
  Agent barre des taches Fresh Windows.
.NOTES
  Prefs: %LOCALAPPDATA%\FreshWindows\watch-agent-user.json
  Lancer avec powershell.exe -STA (sinon l'icone n'apparait pas).
#>
$ErrorActionPreference = 'Stop'
$WatchLog = Join-Path $env:LOCALAPPDATA 'FreshWindows\watch-agent.log'

function Write-WatchLog {
    param([string]$Message)
    try {
        $dir = Split-Path $WatchLog
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $WatchLog -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    } catch { }
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-WatchLog 'Relance en STA'
    $self = $PSCommandPath
    if (-not $self) { $self = $MyInvocation.MyCommand.Path }
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    Start-Process -FilePath $ps -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$self`""
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$RepoRef = if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }
$RepoRawRoot = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef"
$FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
$UserSettingsPath = Join-Path $FreshAppData 'watch-agent-user.json'
$WatchConfigUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/configs/game-mode-watch.json"

$commonPath = $null
if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $commonPath = Join-Path $PSScriptRoot 'GameMode-Common.ps1'
}
if ($commonPath -and (Test-Path -LiteralPath $commonPath)) { . $commonPath }
else {
    $commonUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/scripts/GameMode-Common.ps1"
    $tmp = Join-Path $env:TEMP 'GameMode-Common.ps1'
    Invoke-WebRequest -Uri $commonUrl -OutFile $tmp -UseBasicParsing
    . $tmp
}

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

function Get-WatchRules {
    try {
        return Invoke-RestMethod -Uri $WatchConfigUrl -UseBasicParsing
    }
    catch {
        return @{
            pollIntervalSeconds            = 12
            cpuThresholdPercent            = 28
            cpuSustainedSeconds            = 150
            ramAlertMinMb                  = 6144
            ramAlertPercentOfSystem        = 18
            diskBusyThresholdPercent       = 92
            diskBusySustainedSeconds       = 120
            diskAlertOnlyWhenNotGaming     = $true
            cooldownBetweenSameAlertSeconds = 300
            knownDiskHogs                  = @('SearchIndexer', 'MsMpEng')
        }
    }
}

$script:CpuTrack = @{}
$script:DiskHighSince = $null
$script:LastAlerts = @{}
$script:PendingKill = @{}
$script:GameModeCfg = $null
$script:WatchRules = Get-WatchRules
$script:UserSettings = Get-WatchUserSettings
$script:TotalRamMb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)

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
        $script:NotifyIcon.BalloonTipTitle = $Title
        $script:NotifyIcon.BalloonTipText = $Text
        $script:NotifyIcon.BalloonTipIcon = $Icon
        $script:NotifyIcon.ShowBalloonTip(8000)
    }
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

function Invoke-WatchTick {
    $script:UserSettings = Get-WatchUserSettings
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
                        Show-Balloon -Title 'CPU élevé (hors jeu/comm)' -Text (
                            "$name utilise ~$([math]::Round($pct))% CPU depuis $([math]::Round($cpuSec/60)) min.`nClic droit → " Tuer suggestion " ou " Mode jeu "."
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
                    Show-Balloon -Title 'RAM élevée' -Text ("$name ~$([math]::Round($ramMb)) Mo ($([math]::Round($ramPct))% du système).") -Icon Warning
                    Mark-Alert -Key $key
                }
            }

            if ($p.Responding -eq $false) {
                $key = "hang:$id"
                if ($script:UserSettings.autoSuggestKill -and (Test-AlertCooldown -Key $key -CooldownSec $cooldown)) {
                    $script:PendingKill[$id] = $name
                    Show-Balloon -Title 'Processus ne répond pas' -Text ("$name - proposition de fermeture via le menu de l'icône.") -Icon Error
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
                    Show-Balloon -Title 'Disque saturé' -Text (
                        "Disque ~$([math]::Round($disk))% (hors session jeu).$extra"
                    ) -Icon Warning
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
        $cfg = Get-GameModeKillConfig
        $r = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames
        $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames
        $n = $r.Killed.Count + $idle.Killed.Count
        $extra = if ($idle.Kept.Count) { " Launcher actif : $($idle.Kept[0])." } else { '' }
        Show-Balloon -Title 'Mode jeu' -Text ("$n processus fermés (liste + launchers inactifs).$extra") -Icon Info
    }
    catch {
        Show-Balloon -Title 'Mode jeu' -Text $_.Exception.Message -Icon Error
    }
}

function Invoke-IdleLaunchersOnly {
    try {
        $cfg = Get-GameModeKillConfig
        $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames
        if ($idle.Killed.Count -eq 0) {
            Show-Balloon -Title 'Launchers' -Text 'Aucun launcher gaming superflu ouvert.' -Icon Info
        }
        else {
            Show-Balloon -Title 'Launchers' -Text (
                "Fermés : $($idle.Killed.Count). Gardé : $($idle.Kept -join ', ')"
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

function Invoke-SyncLocalScripts {
    try {
        $corePath = Join-Path $FreshAppData 'Launcher-Core.ps1'
        $coreUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/scripts/lib/Launcher-Core.ps1"
        Invoke-WebRequest -Uri $coreUrl -OutFile $corePath -UseBasicParsing
        Set-Content -LiteralPath (Join-Path $FreshAppData 'Launcher-Core.ps1.ref') -Value $RepoRef -Encoding UTF8 -NoNewline
        . $corePath
        $launcherUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/launcher.ps1"
        $iconUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/assets/fresh-windows.ico"
        Write-FreshWindowsLaunchStub -FreshAppData $FreshAppData -Ref $RepoRef -LauncherUrl $launcherUrl | Out-Null
        Sync-GameModeLocalScripts -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $RepoRef -IconUrl $iconUrl | Out-Null
        Show-Balloon -Title 'Scripts locaux' -Text "Mis à jour (ref $RepoRef). Redémarre l'agent si besoin." -Icon Info
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
    Show-Balloon -Title 'Suggestions' -Text ("$n processus fermés.") -Icon Info
}

# --- UI ---
$script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$iconPath = Join-Path $FreshAppData 'fresh-windows.ico'
try {
    if (Test-Path -LiteralPath $iconPath) {
        $script:NotifyIcon.Icon = New-Object System.Drawing.Icon($iconPath)
    }
    else {
        $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
    }
}
catch {
    Write-WatchLog ("Icone: {0}" -f $_.Exception.Message)
    $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
}
$script:NotifyIcon.Text = 'Fresh Windows'
$script:NotifyIcon.Visible = $true
Write-WatchLog 'NotifyIcon visible'

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miKill = $menu.Items.Add('Mode jeu (liste + launchers inactifs)')
$miKill.Add_Click({ Invoke-GameModeKillNow })

$miLaunchers = $menu.Items.Add('Fermer launchers gaming inactifs')
$miLaunchers.Add_Click({ Invoke-IdleLaunchersOnly })

$miPending = $menu.Items.Add('Tuer suggestions en attente')
$miPending.Add_Click({ Stop-PendingSuggestedProcesses })

$miAuto = $menu.Items.Add('Détection auto : ON')
$miAuto.Add_Click({
    $s = Get-WatchUserSettings
    $s.autoSuggestKill = -not $s.autoSuggestKill
    Set-WatchUserSettings -Settings $s
    $script:UserSettings = $s
    $miAuto.Text = if ($s.autoSuggestKill) { 'Détection auto : ON' } else { 'Détection auto : OFF' }
})

$miMon = $menu.Items.Add('Surveillance : ON')
$miMon.Add_Click({
    $s = Get-WatchUserSettings
    $s.monitorEnabled = -not $s.monitorEnabled
    Set-WatchUserSettings -Settings $s
    $script:UserSettings = $s
    $miMon.Text = if ($s.monitorEnabled) { 'Surveillance : ON' } else { 'Surveillance : OFF' }
})

$menu.Items.Add('-') | Out-Null

$miFw = New-Object System.Windows.Forms.ToolStripMenuItem
$miFw.Text = 'Fresh Windows (terminal admin)'
$null = $menu.Items.Add($miFw)

$miFwMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$miFwMenu.Text = 'Menu interactif (comme le raccourci Bureau)'
$miFwMenu.Add_Click({
    try { Start-FreshWindowsElevated -RepoRef $RepoRef } catch { Show-Balloon -Title 'Fresh Windows' -Text $_.Exception.Message -Icon Error }
})
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
    $item.Add_Click({
        param($sender, $e)
        $m = $sender.Tag
        try { Start-FreshWindowsElevated -SilentMode $m -RepoRef $RepoRef } catch { Show-Balloon -Title 'Fresh Windows' -Text $_.Exception.Message -Icon Error }
    })
    $miFw.DropDownItems.Add($item) | Out-Null
}

$miPs = New-Object System.Windows.Forms.ToolStripMenuItem
$miPs.Text = 'Ouvrir PowerShell (sans admin)'
$miPs.Add_Click({ Start-FreshWindowsPowerShell })
$miFw.DropDownItems.Add($miPs) | Out-Null

$miSync = New-Object System.Windows.Forms.ToolStripMenuItem
$miSync.Text = 'Mettre à jour scripts locaux (ref GitHub)'
$miSync.Add_Click({ Invoke-SyncLocalScripts })
$miFw.DropDownItems.Add($miSync) | Out-Null

$menu.Items.Add('-') | Out-Null
$miExit = $menu.Items.Add('Quitter')
$miExit.Add_Click({
    $script:NotifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

$script:NotifyIcon.ContextMenuStrip = $menu

$miAuto.Text = if ($script:UserSettings.autoSuggestKill) { 'Détection auto : ON' } else { 'Détection auto : OFF' }
$miMon.Text = if ($script:UserSettings.monitorEnabled) { 'Surveillance : ON' } else { 'Surveillance : OFF' }

$pollMs = [math]::Max(5000, [int]$script:WatchRules.pollIntervalSeconds * 1000)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $pollMs
$timer.Add_Tick({ Invoke-WatchTick })
$timer.Start()

if (Test-LocalScriptsStale) {
    Show-Balloon -Title 'Fresh Windows' -Text (
        "Scripts locaux obsolètes ou absents (ref attendue : $RepoRef). Menu → Mettre à jour scripts locaux."
    ) -Icon Warning
}

Invoke-WatchTick
Write-WatchLog 'Application.Run'
try {
    [System.Windows.Forms.Application]::Run()
}
catch {
    Write-WatchLog ("Run: {0}" -f $_.Exception.Message)
    throw
}
