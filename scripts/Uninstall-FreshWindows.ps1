# Desinstallation complete de Fresh Windows (agent, taches, dossier, raccourcis)
# A lancer dans PowerShell ADMIN. Simulation d'abord : .\Uninstall-FreshWindows.ps1 -DryRun
param([switch]$DryRun)
$ErrorActionPreference = 'Continue'
function Do-Step($label, [scriptblock]$action) {
    if ($DryRun) { Write-Host "[SIMULATION] $label" -ForegroundColor Yellow }
    else { Write-Host "[OK] $label" -ForegroundColor Green; & $action }
}
$fresh = Join-Path $env:LOCALAPPDATA 'FreshWindows'

# 1. Arreter l'agent (zone de notification) et tout script Fresh en cours
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'FreshWindows|GameMode-Watch' -and $_.ProcessId -ne $PID } | ForEach-Object {
    $p = $_; Do-Step "Arret du processus $($p.ProcessId) ($($p.Name))" { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
}

# 2. Supprimer les taches planifiees Fresh (noms exacts)
$tasks = 'FreshWindows-SyncLocalScripts','FreshWindows-WatchAgent','FreshWindows-WingetUpgrade','FreshWindows-WinUtilReapply'
Get-ScheduledTask | Where-Object { $_.TaskName -like 'FreshWindows-*' -or $tasks -contains $_.TaskName } | ForEach-Object {
    $t = $_; Do-Step "Suppression de la tache $($t.TaskPath)$($t.TaskName)" { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false }
}

# 3. Supprimer les raccourcis du Bureau
foreach ($lnk in "$env:USERPROFILE\Desktop\Fresh Windows.lnk","$env:USERPROFILE\Desktop\FreshWindows.lnk","$env:PUBLIC\Desktop\Fresh Windows.lnk") {
    if (Test-Path $lnk) { Do-Step "Suppression du raccourci $lnk" { Remove-Item $lnk -Force } }
}

# 4. Supprimer le dossier Fresh Windows (scripts, configs, logs)
if (Test-Path $fresh) {
    Start-Sleep -Seconds 2
    Do-Step "Suppression du dossier $fresh" { Remove-Item $fresh -Recurse -Force }
}

# 5. Dossiers temporaires de test eventuels
Get-ChildItem $env:TEMP -Directory -ErrorAction SilentlyContinue | Where-Object Name -match '^fw-test' | ForEach-Object {
    $d = $_.FullName; Do-Step "Suppression du dossier temporaire $d" { Remove-Item $d -Recurse -Force }
}

# 6. Verification
Write-Host "`n--- Verification ---"
$left = @()
if (Test-Path $fresh) { $left += "Dossier encore present : $fresh" }
Get-ScheduledTask | Where-Object TaskName -like 'FreshWindows-*' | ForEach-Object { $left += "Tache encore presente : $($_.TaskName)" }
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'FreshWindows|GameMode-Watch' -and $_.ProcessId -ne $PID } | ForEach-Object { $left += "Processus encore actif : $($_.ProcessId)" }
if ($DryRun) { Write-Host "Simulation terminee, rien n'a ete supprime." -ForegroundColor Yellow }
elseif ($left.Count -eq 0) { Write-Host "Fresh Windows est entierement supprime." -ForegroundColor Green }
else { $left | ForEach-Object { Write-Host $_ -ForegroundColor Red } }
