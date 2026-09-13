#Requires -Version 5.1
<#
.SYNOPSIS
  Agent barre des tâches Fresh Windows — surveillance légère (10–15 s) + toggle détection auto.
.NOTES
  Pas d'élévation requise. Paramètres utilisateur : %LOCALAPPDATA%\FreshWindows\watch-agent-user.json
#>
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'SilentlyContinue'

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$RepoRef = if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }
$FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
$UserSettingsPath = Join-Path $FreshAppData 'watch-agent-user.json'
$WatchConfigUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/configs/game-mode-watch.json"

$commonPath = Join-Path $PSScriptRoot 'GameMode-Common.ps1'
if (Test-Path -LiteralPath $commonPath) { . $commonPath }
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
    param([string[]]$ProtectNames, $Rules)

    $heur = $Rules.gamingSessionHeuristic
    $minCpu = if ($heur.minProtectProcessCpuPercent) { [double]$heur.minProtectProcessCpuPercent } else { 8 }
    $minRam = if ($heur.minProtectProcessRamMb) { [double]$heur.minProtectProcessRamMb } else { 400 }

    $gamingOnly = @()
    try {
        $cfgObj = Invoke-RestMethod -Uri $script:GameModeConfigUrl -UseBasicParsing
        if ($cfgObj.protect.gaming) { $gamingOnly = @($cfgObj.protect.gaming) }
    } catch { }

    if ($gamingOnly.Count -eq 0) { return $false }

    foreach ($name in $gamingOnly) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            $ramMb = $p.WorkingSet64 / 1MB
            if ($ramMb -ge $minRam) { return $true }
        }
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
    $gaming = Test-GamingSessionActive -ProtectNames $protect -Rules $rules

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
                            "$name utilise ~$([math]::Round($pct))% CPU depuis $([math]::Round($cpuSec/60)) min.`nClic droit → « Tuer suggestion » ou « Mode jeu »."
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
                    Show-Balloon -Title 'Processus ne répond pas' -Text ("$name — proposition de fermeture via le menu de l'icône.") -Icon Error
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
        $n = $r.Killed.Count
        Show-Balloon -Title 'Mode jeu' -Text ("$n processus fermés (liste générique).") -Icon Info
    }
    catch {
        Show-Balloon -Title 'Mode jeu' -Text $_.Exception.Message -Icon Error
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
if (Test-Path -LiteralPath $iconPath) {
    $script:NotifyIcon.Icon = [System.Drawing.Icon]::new($iconPath)
}
else {
    $script:NotifyIcon.Icon = [System.SystemIcons]::Application
}
$script:NotifyIcon.Text = 'Fresh Windows — surveillance'
$script:NotifyIcon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miKill = $menu.Items.Add('Mode jeu (kill liste)')
$miKill.Add_Click({ Invoke-GameModeKillNow })

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

Invoke-WatchTick
[System.Windows.Forms.Application]::Run()
