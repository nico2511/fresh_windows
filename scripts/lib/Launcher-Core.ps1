#Requires -Version 5.1
<#
  Fonctions partagées Fresh Windows (launcher irm, clone local, tâches planifiées).
  Dot-sourcé depuis launcher.ps1 - utilise $RepoRef, $RepoRawRoot, $LauncherUrl, $FreshAppData du parent.
#>
if (-not $script:FreshWindowsLibEpoch) { $script:FreshWindowsLibEpoch = 61 }

function Wait-ForUser {
    if ($Host.Name -eq 'ConsoleHost') {
        Read-Host "`nEntrée pour continuer"
    }
}

function Get-WingetUpgradePowerShellCommand {
    return 'winget source update --disable-interactivity; winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity'
}

function Invoke-WingetUpgradeAll {
    param([switch]$NoPause)

    $ok = $true
    winget source update --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Échec winget source update (code $LASTEXITCODE)" -ForegroundColor Red
        $ok = $false
    }
    winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Échec / partiel winget upgrade (code $LASTEXITCODE)" -ForegroundColor Red
        $ok = $false
    }
    elseif ($ok) {
        Write-Host "winget upgrade terminé." -ForegroundColor Green
    }
    if (-not $NoPause) { Wait-ForUser }
    return $ok
}

function Get-FreshWindowsLaunchStubContent {
    param(
        [string]$Ref,
        [string]$LauncherUrl
    )
    return @"
#Requires -RunAsAdministrator
param([string]`$SilentMode = '')
`$ErrorActionPreference = 'Stop'
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch {}
try {
    `$cu = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
    if (`$cu -in @('Restricted', 'AllSigned')) {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue
    }
} catch {}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
`$env:FRESH_WIN_REF = '$Ref'
if (`$SilentMode) { `$env:FRESH_WIN_MODE = `$SilentMode.Trim().ToLowerInvariant() }
irm '$LauncherUrl' | iex
"@
}

function Write-FreshWindowsLaunchStub {
    param(
        [string]$FreshAppData,
        [string]$Ref,
        [string]$LauncherUrl
    )
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $stubPath = Join-Path $FreshAppData "Launch-FreshWindows.ps1"
    Set-Content -LiteralPath $stubPath -Value (Get-FreshWindowsLaunchStubContent -Ref $Ref -LauncherUrl $LauncherUrl) -Encoding UTF8
    try { Unblock-File -LiteralPath $stubPath -ErrorAction SilentlyContinue } catch { }
    return $stubPath
}

function Get-FreshWindowsScriptsStampPath {
    param([Parameter(Mandatory)][string]$FreshAppData)
    return (Join-Path $FreshAppData 'scripts.stamp')
}

function Write-FreshWindowsScriptsStamp {
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [string]$Epoch = ''
    )
    if ([string]::IsNullOrWhiteSpace($Epoch) -and $script:FreshWindowsLibEpoch) {
        $Epoch = [string]$script:FreshWindowsLibEpoch
    }
    if ([string]::IsNullOrWhiteSpace($Epoch)) { return $false }
    Set-Content -LiteralPath (Get-FreshWindowsScriptsStampPath -FreshAppData $FreshAppData) -Value $Epoch.Trim() -Encoding UTF8 -NoNewline
    return $true
}

function Test-FreshWindowsPathUnderFreshRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$FreshRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($FreshRoot)) { return $false }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetFullPath($FreshRoot.TrimEnd('\', '/'))
        return ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase))
    }
    catch { return $false }
}

function Resolve-FreshWindowsExpectedLocalRoot {
    param([string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'))
    return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'FreshWindows'))
}

function Test-FreshWindowsCanonicalFreshAppData {
    param([Parameter(Mandatory)][string]$FreshAppData)
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return $false }
    try {
        $given = [System.IO.Path]::GetFullPath($FreshAppData.Trim())
        $expected = Resolve-FreshWindowsExpectedLocalRoot
        return ($given -ceq $expected)
    }
    catch { return $false }
}

function Get-FreshWindowsScriptPathFromCommandLine {
    param([string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $m = [regex]::Match($CommandLine, '(?i)-File\s+"([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($CommandLine, "(?i)-File\s+(\S+)")
    if (-not $m.Success) { return $null }
    $p = $m.Groups[1].Value.Trim().Trim('"')
    if ($p.Length -lt 2) { return $null }
    return $p
}

function Stop-FreshWindowsLegacyVoiceProcesses {
    <#
      Arrete voice_worker et hotes voix/IA legacy sous FreshAppData.
      Ne tue pas l'agent maintenance (GameMode-WatchAgent / Launch-GameModeWatch).
    #>
    param(
        [Parameter(Mandatory)][string]$FreshRoot,
        [int[]]$ImmuneProcessIds = @()
    )
    $immune = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($id in $ImmuneProcessIds) { [void]$immune.Add([int]$id) }
    [void]$immune.Add([int]$PID)

    $legacyScriptPattern = '(?i)\\ai\\|\\FreshAgent-(VoiceHost|VoiceWorker|BackgroundWorker)|\\scribe-voice|FreshAgent-Dashboard'

    foreach ($n in @('powershell', 'pwsh')) {
        $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
        foreach ($p in $procs) {
            if ($immune.Contains($p.Id)) { continue }
            $cmd = ''
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction Stop).CommandLine
            }
            catch { continue }
            if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
            $scriptPath = Get-FreshWindowsScriptPathFromCommandLine -CommandLine $cmd
            if (-not $scriptPath) { continue }
            if (-not (Test-FreshWindowsPathUnderFreshRoot -Path $scriptPath -FreshRoot $FreshRoot)) { continue }
            if ($scriptPath -match $legacyScriptPattern -or $cmd -match '(?i)FreshAgent-VoiceHost|FreshAgent-VoiceWorker|FreshAgent-BackgroundWorker') {
                try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
            }
        }
    }

    foreach ($p in @(Get-Process -Name 'voice_worker' -ErrorAction SilentlyContinue)) {
        if ($immune.Contains($p.Id)) { continue }
        $path = ''
        try { $path = $p.Path } catch { }
        if (-not $path) {
            try {
                $path = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction Stop).ExecutablePath
            }
            catch { continue }
        }
        if (-not (Test-FreshWindowsPathUnderFreshRoot -Path $path -FreshRoot (Join-Path $FreshRoot 'bin'))) { continue }
        try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
    }
}

function Remove-FreshWindowsObsoleteLocalAssets {
    <#
      Nettoie sous FreshAppData uniquement les artefacts IA/voix obsoletes.
      Conserve l'agent maintenance systray (scripts, prefs watch, rapport hebdo).
    #>
    param([Parameter(Mandatory)][string]$FreshAppData)

    $errors = [System.Collections.ArrayList]@()
    if (-not (Test-FreshWindowsCanonicalFreshAppData -FreshAppData $FreshAppData)) {
        [void]$errors.Add('FreshAppData doit etre exactement %LOCALAPPDATA%\FreshWindows')
        return @{ ok = $false; errors = @($errors) }
    }
    if (-not (Test-Path -LiteralPath $FreshAppData)) {
        return @{ ok = $true; errors = @() }
    }

    $freshNorm = [System.IO.Path]::GetFullPath($FreshAppData)

    $immune = @(Get-FreshWindowsUninstallImmuneProcessIds)
    try { Stop-FreshWindowsLegacyVoiceProcesses -FreshRoot $freshNorm -ImmuneProcessIds $immune } catch {
        [void]$errors.Add("Stop legacy voix/IA : $($_.Exception.Message)")
    }

    $relFiles = @(
        'agent-ai.user.json',
        'skills-apps.user.json',
        'skills-web.user.json',
        'inventory.json',
        'ai-history.jsonl',
        'ai-prompt.pending.txt',
        'repo.root'
    )
    foreach ($rel in $relFiles) {
        $p = Join-Path $FreshAppData $rel
        if (-not (Test-FreshWindowsPathUnderFreshRoot -Path $p -FreshRoot $freshNorm)) { continue }
        if (Test-Path -LiteralPath $p) {
            try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
            catch { [void]$errors.Add("Suppression $rel : $($_.Exception.Message)") }
        }
    }

    foreach ($relDir in @('ai', 'bin', 'configs\skills')) {
        $p = Join-Path $FreshAppData $relDir
        if (-not (Test-FreshWindowsPathUnderFreshRoot -Path $p -FreshRoot $freshNorm)) { continue }
        if (Test-Path -LiteralPath $p) {
            try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop }
            catch { [void]$errors.Add("Suppression dossier $relDir : $($_.Exception.Message)") }
        }
    }

    foreach ($voiceRelic in @(
            'cache\voice_worker_dl.zip',
            'cache\voice_worker_extract',
            'voice-worker-host.log',
            'fa-models-legacy-notified.txt'
        )) {
        $vp = Join-Path $FreshAppData $voiceRelic
        if (-not (Test-FreshWindowsPathUnderFreshRoot -Path $vp -FreshRoot $freshNorm)) { continue }
        if (Test-Path -LiteralPath $vp) {
            try { Remove-Item -LiteralPath $vp -Recurse -Force -ErrorAction Stop }
            catch { [void]$errors.Add("Suppression relic voix $voiceRelic : $($_.Exception.Message)") }
        }
    }

    $keepLibs = @(
        'FreshAgent-MaintenanceConfig.ps1',
        'FreshAgent-GameSession.ps1',
        'FreshAgent-Optimize.ps1',
        'FreshAgent-Health.ps1'
    )
    $libDir = Join-Path $FreshAppData 'lib'
    if (Test-Path -LiteralPath $libDir) {
        Get-ChildItem -LiteralPath $libDir -Filter 'FreshAgent-*.ps1' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin $keepLibs } |
            ForEach-Object {
                if (-not (Test-FreshWindowsPathUnderFreshRoot -Path $_.FullName -FreshRoot $freshNorm)) { return }
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop }
                catch { [void]$errors.Add("Suppression lib $($_.Name) : $($_.Exception.Message)") }
            }
    }

    $cfgDir = Join-Path $FreshAppData 'configs'
    if (Test-Path -LiteralPath $cfgDir) {
        $keepConfigs = @('game-mode-watch.json', 'maintenance-content.json')
        foreach ($pattern in @('agent-*.json', 'skills-*.json', 'services-allowlist.json')) {
            Get-ChildItem -LiteralPath $cfgDir -Filter $pattern -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin $keepConfigs } |
                ForEach-Object {
                    if (-not (Test-FreshWindowsPathUnderFreshRoot -Path $_.FullName -FreshRoot $freshNorm)) { return }
                    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop }
                    catch { [void]$errors.Add("Suppression config $($_.Name) : $($_.Exception.Message)") }
                }
        }
        foreach ($obsolete in @('agent-content.json')) {
            $op = Join-Path $cfgDir $obsolete
            if (Test-Path -LiteralPath $op) {
                try { Remove-Item -LiteralPath $op -Force -ErrorAction Stop } catch { }
            }
        }
    }

    return @{ ok = ($errors.Count -eq 0); errors = @($errors) }
}

function Test-FreshWindowsIsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal $id
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Stop-FreshWindowsMaintenanceLaunchPrep {
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [int[]]$ImmuneProcessIds = @()
    )
    if (-not (Test-FreshWindowsCanonicalFreshAppData -FreshAppData $FreshAppData)) { return }
    $freshNorm = [System.IO.Path]::GetFullPath($FreshAppData)
    if ($ImmuneProcessIds.Count -eq 0 -and (Get-Command Get-FreshWindowsUninstallImmuneProcessIds -ErrorAction SilentlyContinue)) {
        $ImmuneProcessIds = @(Get-FreshWindowsUninstallImmuneProcessIds)
    }
    Stop-FreshWindowsLegacyVoiceProcesses -FreshRoot $freshNorm -ImmuneProcessIds $ImmuneProcessIds | Out-Null
    $watchScriptPattern = '(?i)GameMode-WatchAgent\.ps1|Launch-GameModeWatch\.ps1'
    foreach ($n in @('powershell', 'pwsh')) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            if ($ImmuneProcessIds -contains $p.Id) { continue }
            $cmd = ''
            try { $cmd = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction Stop).CommandLine } catch { continue }
            $scriptPath = Get-FreshWindowsScriptPathFromCommandLine -CommandLine $cmd
            if (-not $scriptPath) { continue }
            if (-not (Test-FreshWindowsPathUnderFreshRoot -Path $scriptPath -FreshRoot $freshNorm)) { continue }
            if ($scriptPath -match $watchScriptPattern) {
                try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
            }
        }
    }
    $startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Fresh Windows Surveillance.lnk'
    if (Test-FreshWindowsWatchAgentScheduledTaskPresent -FreshAppData $freshNorm) {
        if (Test-Path -LiteralPath $startupLnk) {
            try { Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

function Test-FreshWindowsWatchAgentScheduledTaskPresent {
    param([Parameter(Mandatory)][string]$FreshAppData)
    $cmdPath = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
    $task = Get-ScheduledTask -TaskName 'FreshWindows-WatchAgent' -ErrorAction SilentlyContinue
    if (-not $task) { return $false }
    foreach ($a in @($task.Actions)) {
        $exe = [string]$a.Execute
        if ($exe -and ($exe -eq $cmdPath -or $exe -like '*Start-WatchAgent.cmd*')) { return $true }
    }
    return $false
}

function Import-FreshMaintenanceModules {
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [string]$RepoRawRoot = '',
        [string]$Ref = 'main',
        [string]$IconUrl = ''
    )
    if (-not (Test-FreshWindowsCanonicalFreshAppData -FreshAppData $FreshAppData)) {
        return $false
    }
    $cfg = Join-Path $FreshAppData 'lib\FreshAgent-MaintenanceConfig.ps1'
    if (-not (Test-Path -LiteralPath $cfg)) {
        if ($RepoRawRoot -and (Get-Command Sync-GameModeLocalScripts -ErrorAction SilentlyContinue)) {
            Sync-GameModeLocalScripts -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $Ref -IconUrl $IconUrl | Out-Null
        }
    }
    $known = @{}
    foreach ($cmd in @(Get-Command -CommandType Function -ErrorAction SilentlyContinue)) {
        $known[$cmd.Name] = $true
    }
    foreach ($rel in @(
            'FreshAgent-MaintenanceConfig.ps1',
            'FreshAgent-Health.ps1',
            'FreshAgent-Optimize.ps1',
            'FreshAgent-GameSession.ps1'
        )) {
        $p = Join-Path $FreshAppData "lib\$rel"
        if (-not (Test-Path -LiteralPath $p)) { continue }
        . $p
        foreach ($cmd in @(Get-Command -CommandType Function -ErrorAction SilentlyContinue)) {
            if ($known.ContainsKey($cmd.Name)) { continue }
            $known[$cmd.Name] = $true
            if ($cmd.ModuleName) { continue }
            $dest = "Function:\Global:$($cmd.Name)"
            Set-Item -LiteralPath $dest -Value $cmd.ScriptBlock -Force
        }
    }
    return [bool](Get-Command Invoke-FreshAgentCleanup -ErrorAction SilentlyContinue)
}

function Wait-FreshWindowsWingetIdleForMaintenance {
    param(
        [int]$MaxWaitSeconds = 900,
        [int]$PollSeconds = 15
    )
    $names = @('winget', 'WindowsPackageManager', 'AppInstaller')
    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $busy = $false
        foreach ($n in $names) {
            if (Get-Process -Name $n -ErrorAction SilentlyContinue) { $busy = $true; break }
        }
        if (-not $busy) { return $true }
        Start-Sleep -Seconds $PollSeconds
    }
    return $false
}

function Invoke-FreshMaintenanceTempCleanup {
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [string]$RepoRawRoot = '',
        [string]$Ref = 'main',
        [string]$IconUrl = '',
        [switch]$NoPause
    )
    if (-not (Import-FreshMaintenanceModules -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $Ref -IconUrl $IconUrl)) {
        return @{ ok = $false; message = 'Modules maintenance absents (sync menu 11).' }
    }
    if (-not (Wait-FreshWindowsWingetIdleForMaintenance)) {
        return @{ ok = $false; message = 'Nettoyage temp differe (winget toujours actif apres attente).' }
    }
    return Invoke-FreshAgentCleanup -Temp
}

function Invoke-FreshMaintenanceWeeklyReport {
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [string]$RepoRawRoot = '',
        [string]$Ref = 'main',
        [string]$IconUrl = ''
    )
    if (-not (Import-FreshMaintenanceModules -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $Ref -IconUrl $IconUrl)) {
        return @{ ok = $false; message = 'Modules maintenance absents (sync menu 11).' }
    }
    if (Get-Command New-FreshAgentWeeklyHealthReport -ErrorAction SilentlyContinue) {
        return New-FreshAgentWeeklyHealthReport -FreshAppData $FreshAppData
    }
    return @{ ok = $false; message = 'Rapport indisponible.' }
}

function Start-FreshWindowsUnelevated {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$WorkingDirectory = ''
    )
    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = Split-Path -Parent $FilePath
    }
    if (Get-Command Stop-FreshWindowsMaintenanceLaunchPrep -ErrorAction SilentlyContinue) {
        Stop-FreshWindowsMaintenanceLaunchPrep -FreshAppData $WorkingDirectory | Out-Null
    }
    $cmdPath = Join-Path $WorkingDirectory 'Start-WatchAgent.cmd'
    if (-not (Test-Path -LiteralPath $cmdPath)) {
        throw "Start-WatchAgent.cmd introuvable (sync menu 11 d'abord)."
    }
    Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" `
        -ArgumentList "/trustlevel:0x20000 `"$cmdPath`"" `
        -WorkingDirectory $WorkingDirectory
}

function Register-FreshWindowsWatchAgentLogon {
    param([Parameter(Mandatory)][string]$FreshAppData)
    $taskName = 'FreshWindows-WatchAgent'
    $cmdPath = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
    if (-not (Test-Path -LiteralPath $cmdPath)) {
        throw 'Start-WatchAgent.cmd introuvable.'
    }
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        foreach ($a in @($existing.Actions)) {
            $exe = [string]$a.Execute
            if ($exe -and ($exe -eq $cmdPath -or $exe -like '*Start-WatchAgent.cmd*')) {
                return $taskName
            }
        }
    }
    $helperPs1 = Join-Path $FreshAppData 'Register-WatchAgentTask.ps1'
    $helperCmd = Join-Path $FreshAppData 'Register-WatchAgentTask.cmd'
    @"
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$taskName = 'FreshWindows-WatchAgent'
`$dir = if (`$PSScriptRoot) { `$PSScriptRoot } else { Split-Path -Parent `$MyInvocation.MyCommand.Path }
`$cmdPath = Join-Path `$dir 'Start-WatchAgent.cmd'
Unregister-ScheduledTask -TaskName `$taskName -Confirm:`$false -ErrorAction SilentlyContinue
`$action = New-ScheduledTaskAction -Execute `$cmdPath -WorkingDirectory `$dir
`$trigger = New-ScheduledTaskTrigger -AtLogOn -User `$env:USERNAME
`$trigger.Delay = 'PT45S'
`$principal = New-ScheduledTaskPrincipal -UserId `$env:USERNAME -LogonType Interactive -RunLevel Limited
`$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -DontStopOnIdleEnd
Register-ScheduledTask -TaskName `$taskName -Action `$action -Trigger `$trigger -Principal `$principal -Settings `$settings -Description 'Fresh Windows agent maintenance (Limited).' -Force | Out-Null
"@ | Set-Content -LiteralPath $helperPs1 -Encoding UTF8
    @"
@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Register-WatchAgentTask.ps1"
"@ | Set-Content -LiteralPath $helperCmd -Encoding ASCII
    if (-not (Test-FreshWindowsIsElevated)) {
        & $helperPs1
        return $taskName
    }
    Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" `
        -ArgumentList "/trustlevel:0x20000 `"$helperCmd`"" `
        -Wait -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 800
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        return $taskName
    }
    throw 'Acces refuse pour la tache Limited (fallback Startup possible).'
}

function Publish-FreshGameModeWatchStubs {
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [string]$RepoRef = 'main'
    )
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $watchStub = Join-Path $FreshAppData 'Launch-GameModeWatch.ps1'
    @"
#Requires -Version 5.1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
`$ErrorActionPreference = 'Continue'
`$dir = if (`$PSScriptRoot) { `$PSScriptRoot } else { Split-Path -Parent `$MyInvocation.MyCommand.Path }
`$log = Join-Path `$dir 'watch-agent.log'
function Write-WatchBootLog([string]`$Message) {
    try { Add-Content -LiteralPath `$log -Value ((Get-Date -Format o) + ' ' + `$Message) -Encoding UTF8 } catch { }
}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
`$refFile = Join-Path `$dir 'scripts.ref'
`$ref = if (`$env:FRESH_WIN_REF) { `$env:FRESH_WIN_REF.Trim() } elseif (Test-Path -LiteralPath `$refFile) { (Get-Content -LiteralPath `$refFile -Raw).Trim() } else { 'main' }
`$env:FRESH_WIN_REF = `$ref
`$stampFile = Join-Path `$dir 'scripts.stamp'
`$localEpoch = ''
if (Test-Path -LiteralPath `$stampFile) { `$localEpoch = (Get-Content -LiteralPath `$stampFile -Raw -Encoding UTF8).Trim() }
`$remoteEpoch = `$localEpoch
`$devMode = (`$ref -eq 'local-dev') -or (Test-Path -LiteralPath (Join-Path `$dir 'repo.root'))
if (-not `$devMode) {
    try {
        `$meta = Invoke-RestMethod -Uri ("https://raw.githubusercontent.com/nico2511/fresh_windows/`$ref/configs/maintenance-content.json") -UseBasicParsing -TimeoutSec 5
        if (`$meta -and `$null -ne `$meta.epoch) { `$remoteEpoch = [string]`$meta.epoch }
    }
    catch { }
}
`$stale = (-not `$devMode) -and (`$remoteEpoch -ne `$localEpoch)
`$need = @('GameMode-Common.ps1', 'GameMode-WatchAgent.ps1')
foreach (`$n in `$need) {
    `$p = Join-Path `$dir `$n
    if (`$stale -or -not (Test-Path -LiteralPath `$p) -or ((Get-Item -LiteralPath `$p).Length -lt 80)) {
        Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/nico2511/fresh_windows/`$ref/scripts/`$n") -OutFile `$p -UseBasicParsing
    }
}
& (Join-Path `$dir 'GameMode-WatchAgent.ps1')
"@ | Set-Content -LiteralPath $watchStub -Encoding UTF8
    $cmdPath = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
    @"
@echo off
cd /d "%~dp0"
if not exist "%~dp0Launch-GameModeWatch.ps1" exit /b 1
start "FreshWindowsWatch" /MIN "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch-GameModeWatch.ps1"
exit /b 0
"@ | Set-Content -LiteralPath $cmdPath -Encoding ASCII
    return $true
}

function Sync-GameModeLocalScripts {
    param(
        [string]$FreshAppData,
        [string]$RepoRawRoot,
        [string]$Ref,
        [string]$IconUrl = ''
    )

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null

    if ($IconUrl) {
        $iconPath = Join-Path $FreshAppData "fresh-windows.ico"
        if (-not (Test-Path -LiteralPath $iconPath)) {
            try { Invoke-WebRequest -Uri $IconUrl -OutFile $iconPath -UseBasicParsing } catch { }
        }
    }

    $clean = Remove-FreshWindowsObsoleteLocalAssets -FreshAppData $FreshAppData
    if ($clean -and $clean.errors -and $clean.errors.Count -gt 0) {
        foreach ($e in $clean.errors) {
            Write-Host "!! Nettoyage obsoletes : $e" -ForegroundColor Yellow
        }
    }

    foreach ($scriptName in @(
            'GameMode-Common.ps1',
            'Invoke-GameModeKill.ps1',
            'GameMode-WatchAgent.ps1',
            'Stop-FreshWatchAgent.ps1',
            'Sync-FreshWindowsAgent.ps1',
            'Invoke-FreshWindowsBackgroundAudit.ps1'
        )) {
        $dest = Join-Path $FreshAppData $scriptName
        $url  = "$RepoRawRoot/scripts/$scriptName"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        if (Get-Command Set-FreshScriptUtf8Bom -ErrorAction SilentlyContinue) {
            Set-FreshScriptUtf8Bom -Path $dest
        }
        else {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($dest)
                if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { continue }
                $needsBom = $false
                foreach ($b in $bytes) { if ($b -gt 127) { $needsBom = $true; break } }
                if ($needsBom) {
                    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                    $text = $utf8NoBom.GetString($bytes)
                    $utf8Bom = New-Object System.Text.UTF8Encoding $true
                    [System.IO.File]::WriteAllText($dest, $text, $utf8Bom)
                }
            }
            catch { }
        }
        Write-Host "-> $scriptName" -ForegroundColor DarkGray
    }

    $libDir = Join-Path $FreshAppData 'lib'
    if (-not (Test-Path -LiteralPath $libDir)) { New-Item -ItemType Directory -Path $libDir -Force | Out-Null }
    foreach ($rel in @(
            'lib/Launcher-Core.ps1',
            'lib/FreshAgent-MaintenanceConfig.ps1',
            'lib/FreshAgent-GameSession.ps1',
            'lib/FreshAgent-Optimize.ps1',
            'lib/FreshAgent-Health.ps1',
            'lib/FreshWindows-AppxBloatware.ps1',
            'lib/FreshWindows-BackgroundAudit.ps1'
        )) {
        $leaf = $rel -replace '/', '\'
        $dest = Join-Path $FreshAppData $leaf
        $parent = Split-Path $dest -Parent
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        try {
            Invoke-WebRequest -Uri "$RepoRawRoot/scripts/$rel" -OutFile $dest -UseBasicParsing
            if (Get-Command Set-FreshScriptUtf8Bom -ErrorAction SilentlyContinue) {
                Set-FreshScriptUtf8Bom -Path $dest
            }
        }
        catch {
            Write-Host "!! $rel : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $cfgDir = Join-Path $FreshAppData 'configs'
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    foreach ($cfg in @('game-mode-watch.json', 'maintenance-content.json')) {
        try {
            Invoke-WebRequest -Uri "$RepoRawRoot/configs/$cfg" -OutFile (Join-Path $cfgDir $cfg) -UseBasicParsing
        }
        catch { }
    }

    Set-Content -LiteralPath (Join-Path $FreshAppData 'scripts.ref') -Value $Ref -Encoding UTF8 -NoNewline
    Write-FreshWindowsScriptsStamp -FreshAppData $FreshAppData | Out-Null

    Publish-FreshGameModeKillStub -FreshAppData $FreshAppData | Out-Null
    Publish-FreshGameModeWatchStubs -FreshAppData $FreshAppData -RepoRef $Ref | Out-Null
    return $true
}

function Publish-FreshGameModeKillStub {
    param([Parameter(Mandatory)][string]$FreshAppData)

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null

    $killStub = Join-Path $FreshAppData "Launch-GameModeKill.ps1"
    @"
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$dir = if (`$PSScriptRoot) { `$PSScriptRoot } else { Split-Path -Parent `$MyInvocation.MyCommand.Path }
`$refFile = Join-Path `$dir 'scripts.ref'
`$ref = if (`$env:FRESH_WIN_REF) { `$env:FRESH_WIN_REF.Trim() } elseif (Test-Path -LiteralPath `$refFile) { (Get-Content -LiteralPath `$refFile -Raw).Trim() } else { 'main' }
`$env:FRESH_WIN_REF = `$ref
`$env:FRESH_WIN_NO_PAUSE = '1'
`$need = @('GameMode-Common.ps1', 'Invoke-GameModeKill.ps1')
foreach (`$n in `$need) {
    `$p = Join-Path `$dir `$n
    if (-not (Test-Path -LiteralPath `$p) -or ((Get-Item -LiteralPath `$p).Length -lt 80)) {
        Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/nico2511/fresh_windows/`$ref/scripts/`$n") -OutFile `$p -UseBasicParsing
    }
}
& (Join-Path `$dir 'Invoke-GameModeKill.ps1')
"@ | Set-Content -LiteralPath $killStub -Encoding UTF8

    return $true
}

function Confirm-FreshWindowsUninstallAction {
    param(
        [Parameter(Mandatory)][string]$Summary,
        [string]$Prompt = 'Tape exactement OUI pour confirmer (toute autre reponse annule)'
    )
    Write-Host ''
    Write-Host $Summary -ForegroundColor Yellow
    Write-Host 'Conserve : apps winget, tweaks WinUtil/ShutUp10, CyberScribe.' -ForegroundColor DarkGray
    Write-Host $Prompt -ForegroundColor Yellow
    $line = Read-Host
    if ($null -eq $line) { return $false }
    return ([string]$line) -ceq 'OUI'
}

function Get-FreshWindowsUninstallImmuneProcessIds {
    $ids = [System.Collections.ArrayList]@()
    $cur = $PID
    $guard = 0
    while ($cur -gt 0 -and $guard -lt 64) {
        $guard++
        [void]$ids.Add([int]$cur)
        $parentId = 0
        try {
            $cim = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $cur) -ErrorAction Stop
            $parentId = [int]$cim.ParentProcessId
        }
        catch { break }
        if ($parentId -le 0 -or $ids -contains $parentId) { break }
        $cur = $parentId
    }
    return [int[]]@($ids.ToArray())
}

function New-FreshWindowsUninstallRunStaging {
    param(
        [Parameter(Mandatory)][string]$RepoRawRoot,
        [string]$LocalRepoRoot = '',
        [string]$SessionId = ''
    )
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $SessionId = [guid]::NewGuid().ToString('N')
    }
    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) { $tempRoot = [System.IO.Path]::GetTempPath() }
    if ([string]::IsNullOrWhiteSpace($tempRoot)) { throw 'TEMP indisponible' }
    $stage = Join-Path $tempRoot ("FreshWindows-UninstallRun-{0}" -f $SessionId)
    $libDir = Join-Path $stage 'lib'
    $runScript = Join-Path $stage 'Uninstall-FreshWindows.ps1'
    $libScript = Join-Path $libDir 'FreshWindows-Uninstall.ps1'
    New-Item -ItemType Directory -Path $libDir -Force -ErrorAction Stop | Out-Null
    try {
        if (-not [string]::IsNullOrWhiteSpace($LocalRepoRoot)) {
            $wrapperSrc = Join-Path $LocalRepoRoot 'scripts/Uninstall-FreshWindows.ps1'
            $libSrc = Join-Path $LocalRepoRoot 'scripts/lib/FreshWindows-Uninstall.ps1'
            if (-not (Test-Path -LiteralPath $wrapperSrc) -or -not (Test-Path -LiteralPath $libSrc)) {
                throw 'Fichiers desinstallation locaux introuvables.'
            }
            Copy-Item -LiteralPath $wrapperSrc -Destination $runScript -Force -ErrorAction Stop
            Copy-Item -LiteralPath $libSrc -Destination $libScript -Force -ErrorAction Stop
        }
        else {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            }
            catch { }
            $wrapperUrl = "$RepoRawRoot/scripts/Uninstall-FreshWindows.ps1"
            $libUrl = "$RepoRawRoot/scripts/lib/FreshWindows-Uninstall.ps1"
            Invoke-WebRequest -Uri $wrapperUrl -OutFile $runScript -UseBasicParsing -ErrorAction Stop
            Invoke-WebRequest -Uri $libUrl -OutFile $libScript -UseBasicParsing -ErrorAction Stop
            try { Unblock-File -LiteralPath $runScript -ErrorAction SilentlyContinue } catch { }
            try { Unblock-File -LiteralPath $libScript -ErrorAction SilentlyContinue } catch { }
        }
    }
    catch {
        Remove-FreshWindowsUninstallRunStaging -StageDir $stage
        throw
    }
    return [pscustomobject]@{
        SessionId = $SessionId
        StageDir  = $stage
        RunScript = $runScript
        LibPath   = $libScript
    }
}

function Invoke-FreshWindowsUninstallLibDryRun {
    param(
        [Parameter(Mandatory)][string]$LibPath,
        [string]$ImmuneProcessIdsCsv = ''
    )
    . $LibPath -DryRun -ImmuneProcessIdsCsv $ImmuneProcessIdsCsv
    return (Invoke-FreshWindowsUninstall)
}

function Remove-FreshWindowsUninstallRunStaging {
    param([string]$StageDir = '')
    if ([string]::IsNullOrWhiteSpace($StageDir)) { return $true }
    if (-not (Test-Path -LiteralPath $StageDir)) { return $true }
    try {
        Remove-Item -LiteralPath $StageDir -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Host ("Nettoyage staging impossible : {0}" -f $_.Exception.Message) -ForegroundColor Red
        return $false
    }
    if (Test-Path -LiteralPath $StageDir) {
        Write-Host "Staging partiel encore present apres suppression : $StageDir" -ForegroundColor Red
        return $false
    }
    return $true
}

function Invoke-FreshWindowsUninstallFromMenu {
    param(
        [switch]$DryRun,
        [switch]$ReinstallAfter,
        [Parameter(Mandatory)][string]$RepoRawRoot,
        [string]$LocalRepoRoot = ''
    )
    $immuneFlat = Get-FreshWindowsUninstallImmuneProcessIds
    $immuneCsv = (($immuneFlat | ForEach-Object { [string]$_ }) -join ',')
    if ($DryRun -and -not [string]::IsNullOrWhiteSpace($LocalRepoRoot)) {
        $lib = Join-Path $LocalRepoRoot 'scripts/lib/FreshWindows-Uninstall.ps1'
        if (Test-Path -LiteralPath $lib) {
            Write-Host 'Simulation : execution en memoire (sans copie disque).' -ForegroundColor DarkCyan
            return (Invoke-FreshWindowsUninstallLibDryRun -LibPath $lib -ImmuneProcessIdsCsv $immuneCsv)
        }
    }
    $sessionId = [guid]::NewGuid().ToString('N')
    $staging = $null
    try {
        $staging = New-FreshWindowsUninstallRunStaging -RepoRawRoot $RepoRawRoot -LocalRepoRoot $LocalRepoRoot -SessionId $sessionId
    }
    catch {
        Write-Host "Echec preparation staging desinstallation : $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
    if ($DryRun) {
        Write-Host "Simulation : staging GUID $($staging.StageDir) (supprime apres run)." -ForegroundColor DarkCyan
    }
    $menuExit = 0
    try {
        $argList = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $staging.RunScript,
            '-OwnedSessionId', $sessionId
        )
        if (-not [string]::IsNullOrWhiteSpace($immuneCsv)) {
            $argList += '-ImmuneProcessIdsCsv'
            $argList += $immuneCsv
        }
        if ($DryRun) { $argList += '-DryRun' }
        if ($ReinstallAfter) { $argList += '-ReinstallAfter' }
        if (-not $DryRun) { $argList += '-Confirmed' }
        & powershell.exe @argList
        $menuExit = $LASTEXITCODE
    }
    finally {
        if ($DryRun -and $staging) {
            if (-not (Remove-FreshWindowsUninstallRunStaging -StageDir $staging.StageDir)) {
                Write-Host 'DryRun : staging non supprime proprement (code 1).' -ForegroundColor Red
                $menuExit = 1
            }
        }
    }
    return $menuExit
}

function Open-FreshWindowsUninstallMenu {
    param(
        [Parameter(Mandatory)][string]$RepoRawRoot,
        [string]$LocalRepoRoot = ''
    )
    do {
        Clear-Host
        Write-Host '=== DESINSTALLATION FRESH WINDOWS ===' -ForegroundColor Cyan
        Write-Host 'Retire taches FreshWindows-*, cache %LOCALAPPDATA%\FreshWindows, raccourcis Fresh.' -ForegroundColor DarkGray
        Write-Host 'Ne retire pas les apps winget ni CyberScribe (install winget / dossiers externes).' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '1. Desinstaller puis reinstaller (launcher main GitHub)' -ForegroundColor Cyan
        Write-Host '2. Desinstallation complete' -ForegroundColor Yellow
        Write-Host '3. Simulation uniquement (DryRun)' -ForegroundColor Green
        Write-Host '4. Retour' -ForegroundColor DarkGray
        Write-Host ''
        $c = Read-Host 'Choix'
        switch ($c) {
            '1' {
                $summary = 'Desinstall puis relance le launcher officiel (branche main).'
                if (-not (Confirm-FreshWindowsUninstallAction -Summary $summary)) {
                    Write-Host 'Annule : aucune modification.' -ForegroundColor DarkYellow
                    if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
                    continue
                }
                $code = Invoke-FreshWindowsUninstallFromMenu -ReinstallAfter -RepoRawRoot $RepoRawRoot -LocalRepoRoot $LocalRepoRoot
                if ($code -eq 0 -or $code -eq 5) {
                    Write-Host 'Desinstallation terminee. Fermeture du launcher (relance dans une nouvelle fenetre).' -ForegroundColor Green
                    exit 0
                }
                if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
            }
            '2' {
                $summary = 'Desinstallation complete sans relance automatique.'
                if (-not (Confirm-FreshWindowsUninstallAction -Summary $summary)) {
                    Write-Host 'Annule : aucune modification.' -ForegroundColor DarkYellow
                    if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
                    continue
                }
                $code = Invoke-FreshWindowsUninstallFromMenu -RepoRawRoot $RepoRawRoot -LocalRepoRoot $LocalRepoRoot
                if ($code -eq 0) {
                    Write-Host 'Desinstallation terminee. Vous pouvez relancer Fresh via le one-liner README.' -ForegroundColor Green
                    exit 0
                }
                if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
            }
            '3' {
                $null = Invoke-FreshWindowsUninstallFromMenu -DryRun -RepoRawRoot $RepoRawRoot -LocalRepoRoot $LocalRepoRoot
                if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
            }
            '4' { return }
            default {
                Write-Host 'Choix invalide' -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}
