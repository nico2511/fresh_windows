#Requires -Version 5.1

$script:WingetUpgradeTaskName = 'FreshWindows-WingetUpgrade'
$script:WinUtilReapplyTaskName = 'FreshWindows-WinUtilReapply'

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

    foreach ($name in @($script:WingetUpgradeTaskName, $script:WinUtilReapplyTaskName)) {
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
        Write-Host "Une seule activation crée tout (winget + WinUtil/ShutUp10)." -ForegroundColor DarkGray
        Write-Host "Maintenance = fenêtre visible + log dans %LOCALAPPDATA%\FreshWindows\logs" -ForegroundColor DarkGray
        Write-Host ""
        if (-not (Test-IsAdmin)) {
            Write-Host "⚠️  Pas en admin - l'activation échouera (Accès refusé)." -ForegroundColor Red
            Write-Host ""
        }
        Show-NamedTaskStatus -TaskName $script:WingetUpgradeTaskName -Label "Winget (quotidien 12:00)"
        Show-NamedTaskStatus -TaskName $script:WinUtilReapplyTaskName -Label "WinUtil+ShutUp10 (dimanche 12:00)"
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
