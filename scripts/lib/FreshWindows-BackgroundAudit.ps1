#Requires -Version 5.1
<#
  Audit arriere-plan Fresh Windows (lecture seule par defaut).
  -Apply : desactive uniquement les elements Fresh (taches, prefs, raccourci Startup).
  -Restore : rejoue le journal inverse (meme perimetre Fresh).
#>

function Test-FreshWindowsBackgroundAuditOnWindows {
    if ($env:OS -eq 'Windows_NT') { return $true }
    try {
        return [bool](Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)
    }
    catch {
        return $false
    }
}

function Get-FreshWindowsBackgroundJournalPath {
    param([string]$FreshAppData = $(if (Get-Command Get-FreshAgentAppDataRoot -ErrorAction SilentlyContinue) {
            Get-FreshAgentAppDataRoot
        }
        else {
            Join-Path $env:LOCALAPPDATA 'FreshWindows'
        }))
    return (Join-Path $FreshAppData 'background-audit-journal.jsonl')
}

function Get-FreshWindowsBackgroundCatalog {
    <#
      Metadonnees issues du depot (voir guides/background-audit.md).
    #>
    $startupName = 'Fresh Windows Surveillance.lnk'
    return @(
        @{
            Id              = 'scheduled-task-winget'
            Name            = 'FreshWindows-WingetUpgrade'
            Type            = 'ScheduledTask'
            Frequency       = 'Quotidien 12:00 (StartWhenAvailable)'
            Account         = 'Utilisateur courant (Highest)'
            Impact          = 'Moyen (pic court : winget upgrade --all)'
            Source          = 'scripts/lib/Launcher-Tasks.ps1'
            VerifyPs        = "Get-ScheduledTask -TaskName 'FreshWindows-WingetUpgrade' -ErrorAction SilentlyContinue | Format-List TaskName,State; Get-ScheduledTaskInfo -TaskName 'FreshWindows-WingetUpgrade' -ErrorAction SilentlyContinue"
            DisablePs       = "Disable-ScheduledTask -TaskName 'FreshWindows-WingetUpgrade'"
            EnablePs        = "Enable-ScheduledTask -TaskName 'FreshWindows-WingetUpgrade'"
            ApplySupported  = $true
        },
        @{
            Id              = 'scheduled-task-winutil'
            Name            = 'FreshWindows-WinUtilReapply'
            Type            = 'ScheduledTask'
            Frequency       = 'Dimanche 12:00'
            Account         = 'Utilisateur courant (Highest)'
            Impact          = 'Eleve (maintenance WinUtil + ShutUp10, fenetre visible)'
            Source          = 'scripts/lib/Launcher-Tasks.ps1'
            VerifyPs        = "Get-ScheduledTask -TaskName 'FreshWindows-WinUtilReapply' -ErrorAction SilentlyContinue | Format-List TaskName,State; Get-ScheduledTaskInfo -TaskName 'FreshWindows-WinUtilReapply' -ErrorAction SilentlyContinue"
            DisablePs       = "Disable-ScheduledTask -TaskName 'FreshWindows-WinUtilReapply'"
            EnablePs        = "Enable-ScheduledTask -TaskName 'FreshWindows-WinUtilReapply'"
            ApplySupported  = $true
        },
        @{
            Id              = 'scheduled-task-sync-scripts'
            Name            = 'FreshWindows-SyncLocalScripts'
            Type            = 'ScheduledTask'
            Frequency       = 'Dimanche 12:30'
            Account         = 'Utilisateur courant (Highest)'
            Impact          = 'Faible (sync scripts AppData, reseau)'
            Source          = 'scripts/lib/Launcher-Tasks.ps1'
            VerifyPs        = "Get-ScheduledTask -TaskName 'FreshWindows-SyncLocalScripts' -ErrorAction SilentlyContinue | Format-List TaskName,State"
            DisablePs       = "Disable-ScheduledTask -TaskName 'FreshWindows-SyncLocalScripts'"
            EnablePs        = "Enable-ScheduledTask -TaskName 'FreshWindows-SyncLocalScripts'"
            ApplySupported  = $true
        },
        @{
            Id              = 'scheduled-task-watch-agent'
            Name            = 'FreshWindows-WatchAgent'
            Type            = 'ScheduledTask'
            Frequency       = 'A la connexion (delai 45 s)'
            Account         = 'Utilisateur courant (Limited)'
            Impact          = 'Eleve (demarre l agent systray a chaque session)'
            Source          = 'launcher.ps1 (Register-FreshWindowsWatchAgentLogon)'
            VerifyPs        = "Get-ScheduledTask -TaskName 'FreshWindows-WatchAgent' -ErrorAction SilentlyContinue | Format-List TaskName,State,Actions"
            DisablePs       = "Disable-ScheduledTask -TaskName 'FreshWindows-WatchAgent'"
            EnablePs        = "Enable-ScheduledTask -TaskName 'FreshWindows-WatchAgent'"
            ApplySupported  = $true
        },
        @{
            Id              = 'startup-watch-agent-lnk'
            Name            = $startupName
            Type            = 'StartupFolder'
            Frequency       = 'A chaque connexion (fallback si tache absente)'
            Account         = 'Utilisateur courant'
            Impact          = 'Eleve (double agent si tache + Startup)'
            Source          = 'launcher.ps1 (Install-GameModeShortcuts fallback)'
            VerifyPs        = '$p = Join-Path ([Environment]::GetFolderPath(''Startup'')) ''Fresh Windows Surveillance.lnk''; Test-Path -LiteralPath $p'
            DisablePs       = '# Deplace vers backup FreshWindows (via -Apply du script audit)'
            EnablePs        = '# Restaure depuis journal (-Restore)'
            ApplySupported  = $true
        },
        @{
            Id              = 'prefs-monitor-off'
            Name            = 'watch-agent-user.json :: monitorEnabled'
            Type            = 'UserPrefs'
            Frequency       = 'Effet immediat (agent deja lance)'
            Account         = 'N/A'
            Impact          = 'Moyen (arrete scan CPU/RAM/disque toutes les ~12 s)'
            Source          = 'scripts/GameMode-WatchAgent.ps1'
            VerifyPs        = '$p = Join-Path $env:LOCALAPPDATA ''FreshWindows\watch-agent-user.json''; if (Test-Path $p) { Get-Content $p -Raw } else { ''defaut monitorEnabled=true'' }'
            DisablePs       = '# Met monitorEnabled=false via -Apply'
            EnablePs        = '# Restaure valeur precedente via -Restore'
            ApplySupported  = $true
        },
        @{
            Id              = 'prefs-ai-off'
            Name            = 'agent-ai.user.json :: enabled'
            Type            = 'UserPrefs'
            Frequency       = 'Au prochain cycle IA'
            Account         = 'N/A'
            Impact          = 'Eleve (evite demarrage Ollama auto)'
            Source          = 'scripts/lib/FreshAgent-AiLifecycle.ps1'
            VerifyPs        = '$p = Join-Path $env:LOCALAPPDATA ''FreshWindows\agent-ai.user.json''; if (Test-Path $p) { (Get-Content $p -Raw | ConvertFrom-Json).enabled } else { ''defaut repo: false'' }'
            DisablePs       = '# Met enabled=false via -Apply'
            EnablePs        = '# Restaure via -Restore'
            ApplySupported  = $true
        },
        @{
            Id              = 'prefs-voice-off'
            Name            = 'agent-ai.user.json :: voice.enabled'
            Type            = 'UserPrefs'
            Frequency       = 'Au prochain toggle voix'
            Account         = 'N/A'
            Impact          = 'Eleve (arrete timers STT / voice_worker)'
            Source          = 'configs/agent-ai.json + scripts/ai/FreshAgent-VoiceWorker.ps1'
            VerifyPs        = '$p = Join-Path $env:LOCALAPPDATA ''FreshWindows\agent-ai.user.json''; if (Test-Path $p) { $j = Get-Content $p -Raw | ConvertFrom-Json; $j.voice.enabled } else { ''defaut repo: false'' }'
            DisablePs       = '# Met voice.enabled=false via -Apply'
            EnablePs        = '# Restaure via -Restore'
            ApplySupported  = $true
        },
        @{
            Id              = 'process-watch-agent'
            Name            = 'GameMode-WatchAgent.ps1 (powershell -STA)'
            Type            = 'ResidentProcess'
            Frequency       = 'Permanent tant que systray actif'
            Account         = 'Utilisateur courant'
            Impact          = 'Moyen a eleve (timers UI, scan processus si surveillance ON)'
            Source          = 'scripts/GameMode-WatchAgent.ps1'
            VerifyPs        = 'Get-CimInstance Win32_Process -Filter "Name=''powershell.exe''" | Where-Object { $_.CommandLine -match ''GameMode-WatchAgent|Launch-GameModeWatch'' } | Select-Object ProcessId,CommandLine'
            DisablePs       = 'Arreter via menu systray Quitter (pas de kill auto -Apply)'
            EnablePs        = 'Start-WatchAgent.cmd ou tache FreshWindows-WatchAgent'
            ApplySupported  = $false
        },
        @{
            Id              = 'process-voice-worker'
            Name            = 'voice_worker.exe'
            Type            = 'ResidentProcess'
            Frequency       = 'Quand ecoute vocale active'
            Account         = 'Utilisateur courant'
            Impact          = 'Eleve (faster-whisper / STT, CPU+RAM)'
            Source          = 'scripts/ai/FreshAgent-VoiceWorker.ps1'
            VerifyPs        = 'Get-Process -Name voice_worker -ErrorAction SilentlyContinue | Select-Object Id,CPU,WS'
            DisablePs       = 'Ecoute OFF dans le tray ou prefs-voice-off (-Apply)'
            EnablePs        = 'Ecoute ON dans le tray'
            ApplySupported  = $false
        },
        @{
            Id              = 'process-ollama'
            Name            = 'ollama / ollama app.exe'
            Type            = 'ResidentProcess'
            Frequency       = 'Si IA activee (autoStart)'
            Account         = 'Utilisateur courant'
            Impact          = 'Eleve (modele en RAM, CPU inference)'
            Source          = 'scripts/ai/Ollama-Manager.ps1'
            VerifyPs        = 'Get-Process -Name ollama,''ollama app'' -ErrorAction SilentlyContinue; Test-OllamaApi'
            DisablePs       = 'prefs-ai-off (-Apply) ou quitter Ollama tray'
            EnablePs        = 'Activer IA dans le tray'
            ApplySupported  = $false
        },
        @{
            Id              = 'timer-watch-poll'
            Name            = 'WatchPollTimer'
            Type            = 'WinFormsTimer'
            Frequency       = 'max(5 s, pollIntervalSeconds) — defaut 12 s'
            Account         = 'N/A'
            Impact          = 'Moyen (Get-Process + suivi CPU si surveillance ON)'
            Source          = 'scripts/GameMode-WatchAgent.ps1 + configs/game-mode-watch.json'
            VerifyPs        = '# Actif dans le process WatchAgent; prefs-monitor-off pour couper le scan'
            DisablePs       = 'prefs-monitor-off ou Surveillance OFF (menu tray)'
            EnablePs        = 'Surveillance ON'
            ApplySupported  = $false
        },
        @{
            Id              = 'timer-ptt-hotkey'
            Name            = 'FaPttTimer'
            Type            = 'WinFormsTimer'
            Frequency       = '100 ms si PTT actif (ecoute vocale)'
            Account         = 'N/A'
            Impact          = 'Faible a moyen'
            Source          = 'scripts/ai/FreshAgent-VoiceWorker.ps1'
            VerifyPs        = '# Present seulement si ecoute + push-to-talk'
            DisablePs       = 'prefs-voice-off'
            EnablePs        = 'N/A'
            ApplySupported  = $false
        },
        @{
            Id              = 'timer-stt-poll'
            Name            = 'FaSttPollTimer'
            Type            = 'WinFormsTimer'
            Frequency       = '400 ms pendant ecoute'
            Account         = 'N/A'
            Impact          = 'Moyen'
            Source          = 'scripts/GameMode-WatchAgent.ps1'
            VerifyPs        = '# Present pendant session STT'
            DisablePs       = 'prefs-voice-off'
            EnablePs        = 'N/A'
            ApplySupported  = $false
        },
        @{
            Id              = 'maintenance-weekly-report'
            Name            = 'Rapport sante hebdomadaire'
            Type            = 'Maintenance'
            Frequency       = 'Toutes les 7 j (tick agent)'
            Account         = 'N/A'
            Impact          = 'Faible (snapshot CIM + fichier texte)'
            Source          = 'scripts/lib/FreshAgent-Optimize.ps1'
            VerifyPs        = 'Get-Item ''$env:LOCALAPPDATA\FreshWindows\weekly-health-last.json'' -ErrorAction SilentlyContinue'
            DisablePs       = 'N/A (informatif)'
            EnablePs        = 'N/A'
            ApplySupported  = $false
        },
        @{
            Id              = 'bg-worker-ollama'
            Name            = 'FreshAgent-BackgroundWorker.ps1'
            Type            = 'ChildProcess'
            Frequency       = 'A la demande (EnsureModel, RAG, StartOllama)'
            Account         = 'Utilisateur courant'
            Impact          = 'Eleve pendant pull / index RAG'
            Source          = 'scripts/ai/FreshAgent-BackgroundWorker.ps1'
            VerifyPs        = 'Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match ''FreshAgent-BackgroundWorker'' }'
            DisablePs       = 'Attendre fin ou desactiver IA'
            EnablePs        = 'N/A'
            ApplySupported  = $false
        }
    )
}

function Get-FreshWindowsBackgroundTaskNames {
    return @(
        'FreshWindows-WingetUpgrade',
        'FreshWindows-WinUtilReapply',
        'FreshWindows-SyncLocalScripts',
        'FreshWindows-WatchAgent'
    )
}

function Test-FreshWindowsScheduledTaskIsFresh {
    param([Parameter(Mandatory)][string]$TaskName)
    return ($TaskName -in (Get-FreshWindowsBackgroundTaskNames))
}

function Get-FreshWindowsBackgroundScheduledTaskState {
    param([Parameter(Mandatory)][string]$TaskName)
    if (-not (Test-FreshWindowsBackgroundAuditOnWindows)) {
        return @{ present = $false; state = 'N/A'; lastRun = $null; nextRun = $null }
    }
    if (-not (Test-FreshWindowsScheduledTaskIsFresh -TaskName $TaskName)) {
        throw "Tache hors perimetre Fresh Windows : $TaskName"
    }
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        return @{ present = $false; state = 'Absent'; lastRun = $null; nextRun = $null }
    }
    $info = $null
    try { $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue } catch { }
    return @{
        present = $true
        state   = [string]$task.State
        lastRun = if ($info) { $info.LastRunTime } else { $null }
        nextRun = if ($info) { $info.NextRunTime } else { $null }
    }
}

function Get-FreshWindowsBackgroundStartupLnkPath {
    return (Join-Path ([Environment]::GetFolderPath('Startup')) 'Fresh Windows Surveillance.lnk')
}

function Read-FreshWindowsJsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Merge-FreshWindowsJsonPatch {
    param(
        $Existing,
        [Parameter(Mandatory)]$Patch
    )
    if ($null -eq $Existing) {
        if ($Patch -is [hashtable]) {
            return ($Patch | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
        }
        return $Patch
    }
    $entries = if ($Patch -is [hashtable]) {
        $Patch.GetEnumerator()
    }
    else {
        $Patch.PSObject.Properties
    }
    foreach ($prop in $entries) {
        if ($Patch -is [hashtable]) {
            $name = [string]$prop.Key
            $val = $prop.Value
        }
        else {
            $name = $prop.Name
            $val = $prop.Value
        }
        if ($val -is [pscustomobject] -or $val -is [hashtable]) {
            $sub = $null
            if ($Existing.PSObject.Properties.Name -contains $name) {
                $sub = $Existing.$name
            }
            $hashPatch = @{}
            if ($val -is [pscustomobject]) {
                foreach ($p2 in $val.PSObject.Properties) { $hashPatch[$p2.Name] = $p2.Value }
            }
            else {
                $val.GetEnumerator() | ForEach-Object { $hashPatch[$_.Key] = $_.Value }
            }
            $merged = Merge-FreshWindowsJsonPatch -Existing $sub -Patch $hashPatch
            $Existing | Add-Member -NotePropertyName $name -NotePropertyValue $merged -Force
        }
        else {
            $Existing | Add-Member -NotePropertyName $name -NotePropertyValue $val -Force
        }
    }
    return $Existing
}

function Write-FreshWindowsJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $Object | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-FreshWindowsIsHostTerminalProcess {
    param([string]$ProcessName)
    $n = ([string]$ProcessName).ToLowerInvariant()
    return ($n -in @('windowsterminal.exe', 'wt.exe', 'openconsole.exe'))
}

function Get-FreshWindowsFreshChildProcessRole {
    param([string]$ParentRole)
    switch ([string]$ParentRole) {
        'agent systray' { return 'enfant agent' }
        'enfant agent' { return 'enfant agent' }
        'worker' { return 'enfant worker' }
        'enfant worker' { return 'enfant worker' }
        'voix' { return 'enfant voix' }
        'enfant voix' { return 'enfant voix' }
        'ollama' { return 'enfant ollama' }
        'enfant ollama' { return 'enfant ollama' }
        default { return $null }
    }
}

function Resolve-FreshWindowsKnownProcessRole {
    param(
        [string]$CommandLine,
        [string]$ProcessName,
        [string]$FreshAppData = ''
    )
    $cl = [string]$CommandLine
    if ([string]::IsNullOrWhiteSpace($cl)) { return $null }

    if ($cl -match '(?i)GameMode-WatchAgent|Launch-GameModeWatch|Start-WatchAgent\.cmd') {
        return 'agent systray'
    }
    if ($cl -match 'FreshAgent-BackgroundWorker') { return 'worker' }
    if ($cl -match 'FreshAgent-VoiceWorker|FreshAgent-VoiceHost|voice_worker') { return 'voix' }
    if ($cl -match '(?i)idle-ai-run\.ps1') { return 'worker' }

    if (-not [string]::IsNullOrWhiteSpace($FreshAppData)) {
        $freshNorm = $FreshAppData.TrimEnd('\')
        if ($cl -like "*$freshNorm*") {
            if ($cl -match '(?i)Invoke-FreshWindowsBackgroundAudit|Sync-FreshWindowsAgent\.ps1|Launch-FreshWindows\.ps1|Register-WatchAgentTask|Launch-GameModeKill') {
                return $null
            }
            if ($cl -match '(?i)FreshAgent-BackgroundWorker') { return 'worker' }
            if ($cl -match '(?i)FreshAgent-VoiceWorker|FreshAgent-VoiceHost') { return 'voix' }
            if ($cl -match '(?i)GameMode-WatchAgent|Launch-GameModeWatch') { return 'agent systray' }
        }
    }

    $pn = ([string]$ProcessName).ToLowerInvariant()
    if ($pn -eq 'voice_worker.exe') { return 'voix' }
    if ($pn -eq 'ollama.exe' -or $pn -eq 'ollama app.exe') { return 'ollama' }
    if ($cl -match '(?i)ollama') { return 'ollama' }
    return $null
}

function Get-FreshWindowsFreshProcesses {
    param([string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'))
    $found = @()
    if (-not (Test-FreshWindowsBackgroundAuditOnWindows)) { return $found }

    $seenPids = @{}
    $pidRole = @{}
    try {
        $cim = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
        foreach ($p in $cim) {
            $pidNum = [int]$p.ProcessId
            if ($pidNum -eq $PID) { continue }
            if (Test-FreshWindowsIsHostTerminalProcess -ProcessName $p.Name) { continue }
            $cl = [string]$p.CommandLine
            $role = Resolve-FreshWindowsKnownProcessRole -CommandLine $cl -ProcessName $p.Name -FreshAppData $FreshAppData
            if (-not $role) { continue }
            $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
            $seenPids[$pidNum] = $true
            $pidRole[$pidNum] = $role
            $found += [ordered]@{
                role    = $role
                pid     = $pidNum
                name    = [string]$p.Name
                cpu     = if ($proc) { $proc.CPU } else { $null }
                wsMb    = if ($proc) { [math]::Round($proc.WorkingSet64 / 1MB, 1) } else { $null }
                cmdLine = $cl
            }
        }

        foreach ($p in $cim) {
            $pidNum = [int]$p.ProcessId
            if ($pidNum -eq $PID) { continue }
            if ($seenPids.ContainsKey($pidNum)) { continue }
            if (Test-FreshWindowsIsHostTerminalProcess -ProcessName $p.Name) { continue }
            $parentId = 0
            try { $parentId = [int]$p.ParentProcessId } catch { }
            if ($parentId -le 0 -or -not $pidRole.ContainsKey($parentId)) { continue }
            $childRole = Get-FreshWindowsFreshChildProcessRole -ParentRole $pidRole[$parentId]
            if (-not $childRole) { continue }
            $cl = [string]$p.CommandLine
            $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
            $seenPids[$pidNum] = $true
            $pidRole[$pidNum] = $childRole
            $found += [ordered]@{
                role    = $childRole
                pid     = $pidNum
                name    = [string]$p.Name
                cpu     = if ($proc) { $proc.CPU } else { $null }
                wsMb    = if ($proc) { [math]::Round($proc.WorkingSet64 / 1MB, 1) } else { $null }
                cmdLine = if ([string]::IsNullOrWhiteSpace($cl)) { "(parent PID $parentId)" } else { $cl }
            }
        }
    }
    catch { }

    foreach ($vw in @(Get-Process -Name 'voice_worker' -ErrorAction SilentlyContinue)) {
        if ($vw.Id -eq $PID) { continue }
        if ($seenPids.ContainsKey($vw.Id)) { continue }
        $path = ''
        try { $path = $vw.MainModule.FileName } catch { }
        $found += [ordered]@{
            role    = 'voix'
            pid     = $vw.Id
            name    = $vw.ProcessName
            cpu     = $vw.CPU
            wsMb    = [math]::Round($vw.WorkingSet64 / 1MB, 1)
            cmdLine = if ($path) { $path } else { 'voice_worker.exe' }
        }
        $seenPids[$vw.Id] = $true
    }

    foreach ($ollamaName in @('ollama', 'ollama app')) {
        foreach ($op in @(Get-Process -Name $ollamaName -ErrorAction SilentlyContinue)) {
            if ($op.Id -eq $PID) { continue }
            if ($seenPids.ContainsKey($op.Id)) { continue }
            $path = ''
            try { $path = $op.MainModule.FileName } catch { }
            $found += [ordered]@{
                role    = 'ollama'
                pid     = $op.Id
                name    = $op.ProcessName
                cpu     = $op.CPU
                wsMb    = [math]::Round($op.WorkingSet64 / 1MB, 1)
                cmdLine = if ($path) { $path } else { $ollamaName }
            }
            $seenPids[$op.Id] = $true
        }
    }
    return @($found)
}

function Get-FreshWindowsBackgroundMachineState {
    param([string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'))

    $tasks = @{}
    foreach ($tn in (Get-FreshWindowsBackgroundTaskNames)) {
        $tasks[$tn] = Get-FreshWindowsBackgroundScheduledTaskState -TaskName $tn
    }

    $startupPath = Get-FreshWindowsBackgroundStartupLnkPath
    $watchUserPath = Join-Path $FreshAppData 'watch-agent-user.json'
    $aiUserPath = Join-Path $FreshAppData 'agent-ai.user.json'
    $watchUser = Read-FreshWindowsJsonFile -Path $watchUserPath
    $aiUser = Read-FreshWindowsJsonFile -Path $aiUserPath

    $monitorEnabled = $true
    if ($watchUser -and $null -ne $watchUser.monitorEnabled) { $monitorEnabled = [bool]$watchUser.monitorEnabled }
    $aiEnabled = $null
    $voiceEnabled = $null
    if ($aiUser) {
        if ($null -ne $aiUser.enabled) { $aiEnabled = [bool]$aiUser.enabled }
        if ($aiUser.voice -and $null -ne $aiUser.voice.enabled) { $voiceEnabled = [bool]$aiUser.voice.enabled }
    }

    return [ordered]@{
        at              = (Get-Date).ToString('o')
        freshAppData    = $FreshAppData
        scheduledTasks  = $tasks
        startupLnk      = @{
            path    = $startupPath
            present = (Test-Path -LiteralPath $startupPath)
        }
        prefs           = @{
            monitorEnabled = $monitorEnabled
            aiEnabled      = $aiEnabled
            voiceEnabled   = $voiceEnabled
            watchUserPath  = $watchUserPath
            aiUserPath     = $aiUserPath
        }
        freshProcesses  = @(Get-FreshWindowsFreshProcesses -FreshAppData $FreshAppData)
    }
}

function Format-FreshWindowsBackgroundAuditText {
    param(
        $Catalog = $(Get-FreshWindowsBackgroundCatalog),
        $MachineState = $(Get-FreshWindowsBackgroundMachineState)
    )
    $lines = [System.Collections.ArrayList]@()
    [void]$lines.Add('=== Audit arriere-plan Fresh Windows ===')
    [void]$lines.Add(('Genere : {0}' -f $MachineState.at))
    [void]$lines.Add(('AppData : {0}' -f $MachineState.freshAppData))
    [void]$lines.Add('')
    [void]$lines.Add('--- Taches planifiees Fresh ---')
    foreach ($tn in (Get-FreshWindowsBackgroundTaskNames)) {
        $st = $MachineState.scheduledTasks[$tn]
        [void]$lines.Add(('  {0} : {1} (derniere={2}, prochaine={3})' -f $tn, $st.state, $st.lastRun, $st.nextRun))
    }
    [void]$lines.Add('')
    [void]$lines.Add('--- Startup ---')
    [void]$lines.Add(('  {0} : {1}' -f $MachineState.startupLnk.path, $(if ($MachineState.startupLnk.present) { 'present' } else { 'absent' })))
    [void]$lines.Add('')
    [void]$lines.Add('--- Preferences utilisateur ---')
    [void]$lines.Add(('  monitorEnabled : {0}' -f $MachineState.prefs.monitorEnabled))
    [void]$lines.Add(('  ai.enabled     : {0}' -f $(if ($null -eq $MachineState.prefs.aiEnabled) { '(defaut repo)' } else { $MachineState.prefs.aiEnabled })))
    [void]$lines.Add(('  voice.enabled  : {0}' -f $(if ($null -eq $MachineState.prefs.voiceEnabled) { '(defaut repo)' } else { $MachineState.prefs.voiceEnabled })))
    [void]$lines.Add('')
    [void]$lines.Add('--- Processus Fresh (CPU temps user, WS Mo) ---')
    if ($MachineState.freshProcesses.Count -eq 0) {
        [void]$lines.Add('  (aucun detecte)')
    }
    else {
        foreach ($fp in $MachineState.freshProcesses) {
            [void]$lines.Add(('  [{0}] PID {1} {2} CPU={3} WS={4} Mo' -f $fp.role, $fp.pid, $fp.name, $fp.cpu, $fp.wsMb))
        }
    }
    [void]$lines.Add('')
    [void]$lines.Add('--- Catalogue (impact decroissant, extrait) ---')
    foreach ($c in ($Catalog | Sort-Object { switch ($_.Impact) { 'Eleve' { 0 } 'Moyen a eleve' { 1 } 'Moyen' { 2 } default { 3 } } })) {
        [void]$lines.Add(('  [{0}] {1} ({2}) — {3}' -f $c.Impact, $c.Name, $c.Type, $c.Frequency))
    }
    [void]$lines.Add('')
    [void]$lines.Add('Lecture seule. Desactivation : Invoke-FreshWindowsBackgroundAudit -Apply -TargetIds ...')
    return ($lines -join [Environment]::NewLine)
}

function Add-FreshWindowsBackgroundJournalEntry {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$TargetId,
        $Before,
        $After,
        [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows')
    )
    $path = Get-FreshWindowsBackgroundJournalPath -FreshAppData $FreshAppData
    $dir = Split-Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $entry = [ordered]@{
        id       = [guid]::NewGuid().ToString('N')
        at       = (Get-Date).ToString('o')
        action   = $Action
        targetId = $TargetId
        before   = $Before
        after    = $After
    }
    ($entry | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $path -Encoding UTF8
    return $entry
}

function Get-FreshWindowsBackgroundJournalEntries {
    param([string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'))
    $path = Get-FreshWindowsBackgroundJournalPath -FreshAppData $FreshAppData
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $items = @()
    foreach ($line in @(Get-Content -LiteralPath $path -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $items += ($line | ConvertFrom-Json) } catch { }
    }
    return $items
}

function Invoke-FreshWindowsBackgroundCatalogApply {
    param(
        [Parameter(Mandatory)][string]$TargetId,
        [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'),
        [scriptblock]$ScheduledTaskDisable = $null,
        [scriptblock]$ScheduledTaskEnable = $null
    )

    $catalog = Get-FreshWindowsBackgroundCatalog
    $item = @($catalog | Where-Object { $_.Id -eq $TargetId } | Select-Object -First 1)
    if (-not $item) { throw "TargetId inconnu : $TargetId" }
    if (-not $item.ApplySupported) { throw "TargetId non modifiable via -Apply : $TargetId" }

    switch -Regex ($TargetId) {
        '^scheduled-task-' {
            $taskName = [string]$item.Name
            if (-not (Test-FreshWindowsScheduledTaskIsFresh -TaskName $taskName)) {
                throw "Tache refusee : $taskName"
            }
            $before = Get-FreshWindowsBackgroundScheduledTaskState -TaskName $taskName
            if (-not $before.present) {
                return @{ ok = $false; message = "Tache absente : $taskName"; entry = $null }
            }
            if ($ScheduledTaskDisable) {
                & $ScheduledTaskDisable $taskName
            }
            else {
                Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop
            }
            $after = Get-FreshWindowsBackgroundScheduledTaskState -TaskName $taskName
            $entry = Add-FreshWindowsBackgroundJournalEntry -Action 'disable-task' -TargetId $TargetId `
                -Before $before -After $after -FreshAppData $FreshAppData
            return @{ ok = $true; message = "Tache desactivee : $taskName"; entry = $entry }
        }
        '^startup-watch-agent-lnk$' {
            $lnk = Get-FreshWindowsBackgroundStartupLnkPath
            $before = @{ present = (Test-Path -LiteralPath $lnk); path = $lnk }
            if (-not $before.present) {
                return @{ ok = $false; message = 'Raccourci Startup deja absent.'; entry = $null }
            }
            $backupDir = Join-Path $FreshAppData 'background-audit-backup'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            $backup = Join-Path $backupDir 'Fresh Windows Surveillance.lnk'
            Move-Item -LiteralPath $lnk -Destination $backup -Force
            $after = @{ present = $false; backup = $backup }
            $entry = Add-FreshWindowsBackgroundJournalEntry -Action 'move-startup-lnk' -TargetId $TargetId `
                -Before $before -After $after -FreshAppData $FreshAppData
            return @{ ok = $true; message = "Startup deplace vers $backup"; entry = $entry }
        }
        '^prefs-monitor-off$' {
            $path = Join-Path $FreshAppData 'watch-agent-user.json'
            $beforeObj = Read-FreshWindowsJsonFile -Path $path
            $before = @{ path = $path; monitorEnabled = $(if ($beforeObj -and $null -ne $beforeObj.monitorEnabled) { [bool]$beforeObj.monitorEnabled } else { $true }) }
            $patch = @{ monitorEnabled = $false }
            $merged = Merge-FreshWindowsJsonPatch -Existing $beforeObj -Patch $patch
            Write-FreshWindowsJsonFile -Path $path -Object $merged
            $entry = Add-FreshWindowsBackgroundJournalEntry -Action 'set-pref' -TargetId $TargetId -Before $before `
                -After @{ monitorEnabled = $false } -FreshAppData $FreshAppData
            return @{ ok = $true; message = 'monitorEnabled=false'; entry = $entry }
        }
        '^prefs-ai-off$' {
            $path = Join-Path $FreshAppData 'agent-ai.user.json'
            $beforeObj = Read-FreshWindowsJsonFile -Path $path
            $beforeVal = if ($beforeObj -and $null -ne $beforeObj.enabled) { [bool]$beforeObj.enabled } else { $null }
            $merged = Merge-FreshWindowsJsonPatch -Existing $beforeObj -Patch @{ enabled = $false }
            Write-FreshWindowsJsonFile -Path $path -Object $merged
            $entry = Add-FreshWindowsBackgroundJournalEntry -Action 'set-pref' -TargetId $TargetId `
                -Before @{ enabled = $beforeVal } -After @{ enabled = $false } -FreshAppData $FreshAppData
            return @{ ok = $true; message = 'IA enabled=false'; entry = $entry }
        }
        '^prefs-voice-off$' {
            $path = Join-Path $FreshAppData 'agent-ai.user.json'
            $beforeObj = Read-FreshWindowsJsonFile -Path $path
            $beforeVal = if ($beforeObj -and $beforeObj.voice -and $null -ne $beforeObj.voice.enabled) { [bool]$beforeObj.voice.enabled } else { $null }
            $merged = Merge-FreshWindowsJsonPatch -Existing $beforeObj -Patch @{ voice = @{ enabled = $false } }
            Write-FreshWindowsJsonFile -Path $path -Object $merged
            $entry = Add-FreshWindowsBackgroundJournalEntry -Action 'set-pref' -TargetId $TargetId `
                -Before @{ voice = @{ enabled = $beforeVal } } -After @{ voice = @{ enabled = $false } } -FreshAppData $FreshAppData
            return @{ ok = $true; message = 'voice.enabled=false'; entry = $entry }
        }
        default {
            throw "Apply non implemente pour $TargetId"
        }
    }
}

function Restore-FreshWindowsBackgroundJournalEntry {
    param(
        [Parameter(Mandatory)]$Entry,
        [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'),
        [scriptblock]$ScheduledTaskEnable = $null
    )
    $tid = [string]$Entry.targetId
    $action = [string]$Entry.action

    if ($action -eq 'disable-task' -and $Entry.before) {
        $taskName = $null
        $cat = Get-FreshWindowsBackgroundCatalog | Where-Object { $_.Id -eq $tid } | Select-Object -First 1
        if ($cat) { $taskName = [string]$cat.Name }
        if (-not $taskName) { throw 'Restore task : nom introuvable' }
        if (-not (Test-FreshWindowsScheduledTaskIsFresh -TaskName $taskName)) { throw 'Restore task hors perimetre' }
        if ($ScheduledTaskEnable) { & $ScheduledTaskEnable $taskName }
        else { Enable-ScheduledTask -TaskName $taskName -ErrorAction Stop }
        return @{ ok = $true; message = "Tache reactivee : $taskName" }
    }
    if ($action -eq 'move-startup-lnk' -and $Entry.after -and $Entry.after.backup) {
        $lnk = Get-FreshWindowsBackgroundStartupLnkPath
        $backup = [string]$Entry.after.backup
        if (Test-Path -LiteralPath $backup) {
            if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
            Move-Item -LiteralPath $backup -Destination $lnk -Force
            return @{ ok = $true; message = 'Raccourci Startup restaure.' }
        }
        return @{ ok = $false; message = "Backup introuvable : $backup" }
    }
    if ($action -eq 'set-pref') {
        if ($tid -eq 'prefs-monitor-off') {
            $path = Join-Path $FreshAppData 'watch-agent-user.json'
            $cur = Read-FreshWindowsJsonFile -Path $path
            $val = $true
            if ($Entry.before -and $null -ne $Entry.before.monitorEnabled) { $val = [bool]$Entry.before.monitorEnabled }
            $merged = Merge-FreshWindowsJsonPatch -Existing $cur -Patch @{ monitorEnabled = $val }
            Write-FreshWindowsJsonFile -Path $path -Object $merged
            return @{ ok = $true; message = "monitorEnabled=$val" }
        }
        if ($tid -eq 'prefs-ai-off') {
            $path = Join-Path $FreshAppData 'agent-ai.user.json'
            $cur = Read-FreshWindowsJsonFile -Path $path
            $val = if ($Entry.before -and $null -ne $Entry.before.enabled) { [bool]$Entry.before.enabled } else { $false }
            $merged = Merge-FreshWindowsJsonPatch -Existing $cur -Patch @{ enabled = $val }
            Write-FreshWindowsJsonFile -Path $path -Object $merged
            return @{ ok = $true; message = "ai.enabled=$val" }
        }
        if ($tid -eq 'prefs-voice-off') {
            $path = Join-Path $FreshAppData 'agent-ai.user.json'
            $cur = Read-FreshWindowsJsonFile -Path $path
            $val = $false
            if ($Entry.before -and $Entry.before.voice -and $null -ne $Entry.before.voice.enabled) {
                $val = [bool]$Entry.before.voice.enabled
            }
            $merged = Merge-FreshWindowsJsonPatch -Existing $cur -Patch @{ voice = @{ enabled = $val } }
            Write-FreshWindowsJsonFile -Path $path -Object $merged
            return @{ ok = $true; message = "voice.enabled=$val" }
        }
    }
    return @{ ok = $false; message = "Entree journal non reversible : $action / $tid" }
}

function Restore-FreshWindowsBackgroundFromJournal {
    param(
        [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'),
        [int]$Last = 0,
        [scriptblock]$ScheduledTaskEnable = $null
    )
    $entries = @(Get-FreshWindowsBackgroundJournalEntries -FreshAppData $FreshAppData)
    if ($entries.Count -eq 0) {
        return @{ ok = $false; message = 'Journal vide.'; results = @() }
    }
    $toRestore = if ($Last -gt 0) { @($entries | Select-Object -Last $Last) } else { $entries }
    $results = @()
    for ($i = $toRestore.Count - 1; $i -ge 0; $i--) {
        $r = Restore-FreshWindowsBackgroundJournalEntry -Entry $toRestore[$i] -FreshAppData $FreshAppData `
            -ScheduledTaskEnable $ScheduledTaskEnable
        $results += $r
    }
    return @{ ok = $true; message = "Restore : $($results.Count) entree(s)"; results = $results }
}

function Invoke-FreshWindowsBackgroundAudit {
    param(
        [switch]$Apply,
        [switch]$Restore,
        [string[]]$TargetIds = @(),
        [switch]$NoConfirm,
        [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'),
        [string]$ReportPath = '',
        [scriptblock]$ScheduledTaskDisable = $null,
        [scriptblock]$ScheduledTaskEnable = $null
    )

    if ($Apply -and $Restore) {
        throw 'Utiliser -Apply ou -Restore, pas les deux.'
    }

    if ($Restore) {
        $rr = Restore-FreshWindowsBackgroundFromJournal -FreshAppData $FreshAppData `
            -ScheduledTaskEnable $ScheduledTaskEnable
        Write-Host $rr.message
        foreach ($r in $rr.results) { Write-Host ('  {0}' -f $r.message) }
        return $rr
    }

    $state = Get-FreshWindowsBackgroundMachineState -FreshAppData $FreshAppData
    $text = Format-FreshWindowsBackgroundAuditText -MachineState $state
    Write-Host $text

    if (-not $ReportPath) {
        $ReportPath = Join-Path $FreshAppData ('background-audit-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    try {
        New-Item -ItemType Directory -Path (Split-Path $ReportPath -Parent) -Force | Out-Null
        Set-Content -LiteralPath $ReportPath -Value $text -Encoding UTF8
        Write-Host ""
        Write-Host "Rapport fichier : $ReportPath" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Ecriture rapport : $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if (-not $Apply) {
        return @{ ok = $true; mode = 'read-only'; state = $state; reportPath = $ReportPath }
    }

    $applicable = @(Get-FreshWindowsBackgroundCatalog | Where-Object { $_.ApplySupported } | ForEach-Object { $_.Id })
    $chosen = if ($TargetIds -and $TargetIds.Count -gt 0) { @($TargetIds) } else { $applicable }

    foreach ($id in $chosen) {
        if ($id -notin $applicable) {
            throw "TargetId hors perimetre ou non applicable : $id"
        }
    }

    if (-not $NoConfirm) {
        Write-Host ""
        Write-Host "APPLY va desactiver / modifier :" -ForegroundColor Yellow
        foreach ($id in $chosen) { Write-Host "  - $id" }
        $ans = Read-Host "Confirmer (oui/non)"
        if ($ans -notmatch '^(oui|o|yes|y)$') {
            Write-Host "Annule." -ForegroundColor DarkGray
            return @{ ok = $false; mode = 'apply-cancelled'; state = $state }
        }
    }

    $results = @()
    foreach ($id in $chosen) {
        try {
            $r = Invoke-FreshWindowsBackgroundCatalogApply -TargetId $id -FreshAppData $FreshAppData `
                -ScheduledTaskDisable $ScheduledTaskDisable -ScheduledTaskEnable $ScheduledTaskEnable
            $results += $r
            Write-Host ('[OK] {0}' -f $r.message) -ForegroundColor Green
        }
        catch {
            Write-Host ('[KO] {0} : {1}' -f $id, $_.Exception.Message) -ForegroundColor Red
            $results += @{ ok = $false; message = $_.Exception.Message; targetId = $id }
        }
    }
    return @{ ok = $true; mode = 'apply'; results = $results; state = $state; reportPath = $ReportPath }
}

function Open-FreshWindowsBackgroundAuditMenu {
    do {
        Clear-Host
        Write-Host "=== AUDIT ARRIERE-PLAN FRESH WINDOWS ===" -ForegroundColor Cyan
        Write-Host "Lecture seule par defaut. Voir guides/background-audit.md" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "1. Rapport (console + fichier)" -ForegroundColor Green
        Write-Host "2. Desactiver elements lourds (tache agent + surveillance + IA/voix)" -ForegroundColor Yellow
        Write-Host "3. Restaurer depuis le journal" -ForegroundColor Magenta
        Write-Host "4. Retour" -ForegroundColor DarkGray
        Write-Host ""
        $c = Read-Host "Choix"
        switch ($c) {
            '1' {
                Invoke-FreshWindowsBackgroundAudit -FreshAppData $FreshAppData | Out-Null
                Wait-ForUser
            }
            '2' {
                $targets = @(
                    'scheduled-task-watch-agent',
                    'prefs-monitor-off',
                    'prefs-voice-off',
                    'prefs-ai-off'
                )
                Invoke-FreshWindowsBackgroundAudit -Apply -TargetIds $targets -FreshAppData $FreshAppData | Out-Null
                Wait-ForUser
            }
            '3' {
                Restore-FreshWindowsBackgroundFromJournal -FreshAppData $FreshAppData | Out-Null
                Wait-ForUser
            }
            '4' { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}
