#Requires -Version 5.1

$script:WingetUpgradeTaskName = 'FreshWindows-WingetUpgrade'
$script:WinUtilReapplyTaskName = 'FreshWindows-WinUtilReapply'
$script:SyncLocalScriptsTaskName = 'FreshWindows-SyncLocalScripts'

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = [Security.Principal.WindowsPrincipal]::new($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Get-CommonTaskSettings {
    param([int]$Hours = 3)
    return (New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -RunOnlyIfNetworkAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours $Hours) `
        -MultipleInstances IgnoreNew)
}

function Get-SyncLocalScriptsPowerShellCommand {
    # Resync scripts mode jeu dans %LOCALAPPDATA%\FreshWindows (ref figee a l'enregistrement)
    return @"
`$ErrorActionPreference='Stop'; try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}; `$ref='$RepoRef'; `$fresh=Join-Path `$env:LOCALAPPDATA 'FreshWindows'; New-Item -ItemType Directory -Path `$fresh -Force | Out-Null; `$raw='https://raw.githubusercontent.com/nico2511/fresh_windows/'+`$ref; foreach (`$n in @('GameMode-Common.ps1','Invoke-GameModeKill.ps1','GameMode-WatchAgent.ps1')) { Invoke-WebRequest -Uri (`$raw+'/scripts/'+`$n) -OutFile (Join-Path `$fresh `$n) -UseBasicParsing }; `$agentScripts=@('lib/FreshAgent-Config.ps1','lib/FreshAgent-SkillsEngine.ps1','lib/FreshAgent-SkillHandlers.ps1','lib/FreshAgent-GameSession.ps1','ai/Ollama-Manager.ps1','ai/FreshAgent-OllamaBridge.ps1','ai/Windows-Stt.ps1'); foreach (`$rel in `$agentScripts) { `$dest=Join-Path `$fresh (`$rel -replace '/','\'); New-Item -ItemType Directory -Path (Split-Path `$dest -Parent) -Force | Out-Null; Invoke-WebRequest -Uri (`$raw+'/scripts/'+(`$rel -replace '\\','/')) -OutFile `$dest -UseBasicParsing }; `$cfgPaths=@('configs/agent-ai.json','configs/skills-apps.json','configs/skills-web.json','configs/skills/registry.json'); foreach (`$rel in `$cfgPaths) { `$dest=Join-Path `$fresh (`$rel -replace '/','\'); New-Item -ItemType Directory -Path (Split-Path `$dest -Parent) -Force | Out-Null; Invoke-WebRequest -Uri (`$raw+'/'+(`$rel -replace '\\','/')) -OutFile `$dest -UseBasicParsing }; Set-Content -LiteralPath (Join-Path `$fresh 'scripts.ref') -Value `$ref -Encoding UTF8 -NoNewline
"@
}

function Register-AllScheduledTasks {
    param([switch]$NoPause)

    if (-not (Test-IsAdmin)) {
        Write-Host "`nAccès refusé : relance le script en PowerShell Administrateur." -ForegroundColor Red
        Write-Host "  Clic droit → Exécuter en tant qu'administrateur" -ForegroundColor Yellow
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings  = Get-CommonTaskSettings -Hours 3
    $ok = $true

    Write-Host "`n→ Création des tâches planifiées (une fois)..." -ForegroundColor Cyan

    try {
        $wingetCmd = Get-WingetUpgradePowerShellCommand
        $wingetArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$wingetCmd`""
        $wingetAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $wingetArg
        $wingetTrigger = New-ScheduledTaskTrigger -Daily -At "12:00"

        Register-ScheduledTask `
            -TaskName $script:WingetUpgradeTaskName `
            -Action $wingetAction `
            -Trigger $wingetTrigger `
            -Settings $settings `
            -Principal $principal `
            -Description "Fresh Windows: winget source update + upgrade --all (StartWhenAvailable)." `
            -Force -ErrorAction Stop | Out-Null

        Write-Host "  [OK] $script:WingetUpgradeTaskName - tous les jours 12:00 (+ rattrapage)" -ForegroundColor Green
    }
    catch {
        Write-Host "  [KO] Winget : $($_.Exception.Message)" -ForegroundColor Red
        $ok = $false
    }

    try {
        $maintInner = "`$env:FRESH_WIN_REF='$RepoRef'; `$env:FRESH_WIN_MODE='maintenance'; irm '$LauncherUrl' | iex"
        $maintArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -Command `"$maintInner`""
        $maintAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $maintArg
        $maintTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "12:00"

        Register-ScheduledTask `
            -TaskName $script:WinUtilReapplyTaskName `
            -Action $maintAction `
            -Trigger $maintTrigger `
            -Settings $settings `
            -Principal $principal `
            -Description "Fresh Windows: WinUtil + ShutUp10. Fenêtre visible + log dans %LOCALAPPDATA%\FreshWindows\logs." `
            -Force -ErrorAction Stop | Out-Null

        Write-Host "  [OK] $script:WinUtilReapplyTaskName - dimanche 12:00 (+ rattrapage)" -ForegroundColor Green
        Write-Host "       Fenêtre PowerShell visible + log FreshWindows\logs" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "  [KO] WinUtil/ShutUp10 : $($_.Exception.Message)" -ForegroundColor Red
        $ok = $false
    }

    try {
        $syncCmd = Get-SyncLocalScriptsPowerShellCommand
        $syncArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$syncCmd`""
        $syncAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $syncArg
        $syncTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "12:30"
        $syncSettings = Get-CommonTaskSettings -Hours 1

        Register-ScheduledTask `
            -TaskName $script:SyncLocalScriptsTaskName `
            -Action $syncAction `
            -Trigger $syncTrigger `
            -Settings $syncSettings `
            -Principal $principal `
            -Description "Fresh Windows: resync scripts locaux Mode jeu (%LOCALAPPDATA%\FreshWindows)." `
            -Force -ErrorAction Stop | Out-Null

        Write-Host "  [OK] $script:SyncLocalScriptsTaskName - dimanche 12:30 (+ rattrapage)" -ForegroundColor Green
    }
    catch {
        Write-Host "  [KO] Sync scripts : $($_.Exception.Message)" -ForegroundColor Red
        $ok = $false
    }

    if ($ok) {
        Write-Host "`nTout est en place. PC éteint à l'heure prévue → rattrapage au prochain allumage." -ForegroundColor Cyan
    }
    else {
        Write-Host "`nCertaines tâches ont échoué (souvent: pas admin)." -ForegroundColor Yellow
    }

    if (-not $NoPause) { Wait-ForUser }
    return $ok
}

function Unregister-AllScheduledTasks {
    param([switch]$NoPause)

    foreach ($name in @($script:WingetUpgradeTaskName, $script:WinUtilReapplyTaskName, $script:SyncLocalScriptsTaskName)) {
        try {
            $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
            if (-not $existing) {
                Write-Host "  (déjà absente) $name" -ForegroundColor DarkGray
            }
            else {
                Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
                Write-Host "  [OK] supprimée : $name" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "  [KO] $name : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if (-not $NoPause) { Wait-ForUser }
}

function Show-NamedTaskStatus {
    param([string]$TaskName, [string]$Label)
    Write-Host "-- $Label --" -ForegroundColor Cyan
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "  absente" -ForegroundColor Yellow
        return
    }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host "  $($task.State) | dernière $($info.LastRunTime) | prochaine $($info.NextRunTime)" -ForegroundColor Green
}

function Open-ScheduledTasksMenu {
    do {
        Clear-Host
        Write-Host "=== TÂCHES PLANIFIÉES ===" -ForegroundColor Cyan
        Write-Host "Une seule activation crée tout (winget + maintenance + sync scripts)." -ForegroundColor DarkGray
        Write-Host "Maintenance = fenêtre visible + log dans %LOCALAPPDATA%\FreshWindows\logs" -ForegroundColor DarkGray
        Write-Host ""
        if (-not (Test-IsAdmin)) {
            Write-Host "⚠️  Pas en admin - l'activation échouera (Accès refusé)." -ForegroundColor Red
            Write-Host ""
        }
        Show-NamedTaskStatus -TaskName $script:WingetUpgradeTaskName -Label "Winget (quotidien 12:00)"
        Show-NamedTaskStatus -TaskName $script:WinUtilReapplyTaskName -Label "WinUtil+ShutUp10 (dimanche 12:00)"
        Show-NamedTaskStatus -TaskName $script:SyncLocalScriptsTaskName -Label "Sync scripts locaux (dimanche 12:30)"
        Write-Host ""
        Write-Host "1. Activer toutes les tâches" -ForegroundColor Green
        Write-Host "2. Lancer la maintenance maintenant (WinUtil + ShutUp10)" -ForegroundColor Yellow
        Write-Host "3. Supprimer toutes les tâches" -ForegroundColor Red
        Write-Host "4. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" { Register-AllScheduledTasks }
            "2" { Invoke-MaintenanceReapply }
            "3" { Unregister-AllScheduledTasks }
            "4" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}
