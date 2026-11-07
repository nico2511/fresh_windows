#Requires -RunAsAdministrator
#Requires -Version 5.1
# Desinstallation Fresh Windows (agent, taches, cache local, raccourcis Fresh)
# Simulation : -DryRun. Suppression : -Confirmed. Reinstall : -ReinstallAfter apres succes verifie.
param(
    [switch]$DryRun,
    [switch]$ReinstallAfter,
    [switch]$Confirmed
)

$ErrorActionPreference = 'Continue'
$script:FreshUninstallSelfPid = $PID
$script:FreshUninstallRepoMainLauncher = 'https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1'
$script:FreshUninstallStepFailures = [System.Collections.ArrayList]@()
$script:FreshUninstallVerificationErrors = [System.Collections.ArrayList]@()

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
    }
    catch { return $false }
    if ($full.Length -lt $rootFull.Length) { return $false }
    if ($full.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $sep = $full[$rootFull.Length]
    if ($sep -ne '\' -and $sep -ne '/') { return $false }
    return $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Test-FreshUninstallCommandTargetsFreshRoot {
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$FreshRoot
    )
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    try {
        $rootFull = [System.IO.Path]::GetFullPath($FreshRoot.TrimEnd('\', '/'))
    }
    catch { return $false }
    $esc = [regex]::Escape($rootFull)
    return ($CommandLine -match "(?i)${esc}(\\|/|`"|'|\s|$)")
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
    $agentPattern = 'GameMode-WatchAgent|Launch-GameModeWatch|Start-WatchAgent\.cmd'
    $hostPattern = 'FreshAgent-VoiceHost'
    $launchPattern = 'Launch-FreshWindows\.ps1|Launch-GameModeKill\.ps1'

    foreach ($n in @('powershell', 'pwsh')) {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            if (Test-FreshUninstallProcessImmune -ProcessId $p.Id) { continue }
            $cmd = $null
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction Stop).CommandLine
            }
            catch {
                continue
            }
            if (-not (Test-FreshUninstallCommandTargetsFreshRoot -CommandLine $cmd -FreshRoot $FreshRoot)) { continue }
            if ($cmd -match $agentPattern -or $cmd -match $hostPattern -or $cmd -match $launchPattern) {
                [void]$out.Add([pscustomobject]@{ ProcessId = $p.Id; Name = $p.ProcessName; CommandLine = $cmd })
            }
        }
    }

    foreach ($p in @(Get-Process -Name 'voice_worker' -ErrorAction SilentlyContinue)) {
        if (Test-FreshUninstallProcessImmune -ProcessId $p.Id) { continue }
        $path = $null
        try { $path = $p.Path } catch { }
        if (-not $path) {
            try {
                $path = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction Stop).ExecutablePath
            }
            catch { continue }
        }
        try { $path = [System.IO.Path]::GetFullPath($path) } catch { continue }
        if (-not (Test-FreshUninstallPathUnderRoot -Path $path -Root (Join-Path $FreshRoot 'bin'))) { continue }
        [void]$out.Add([pscustomobject]@{ ProcessId = $p.Id; Name = $p.ProcessName; CommandLine = $path })
    }
    return @($out | Sort-Object ProcessId -Unique)
}

function Add-FreshUninstallStepFailure {
    param([string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { return }
    [void]$script:FreshUninstallStepFailures.Add($Label)
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
    try {
        & $Action
        Write-Host "[OK] $Label" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ECHEC] $Label : $($_.Exception.Message)" -ForegroundColor Red
        Add-FreshUninstallStepFailure -Label $Label
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

function Get-FreshUninstallScheduledTasks {
    try {
        if (-not (Get-Command Get-ScheduledTask -ErrorAction Stop)) {
            throw 'Get-ScheduledTask indisponible'
        }
        return @(
            Get-ScheduledTask -ErrorAction Stop |
                Where-Object { $_.TaskName -like 'FreshWindows-*' }
        )
    }
    catch {
        [void]$script:FreshUninstallVerificationErrors.Add('verification taches planifiees indisponible')
        return $null
    }
}

function Get-FreshUninstallVerification {
    param([Parameter(Mandatory)][string]$FreshRoot)
    $issues = [System.Collections.ArrayList]@()
    $unavailable = $false

    if ($script:FreshUninstallVerificationErrors.Count -gt 0) {
        $unavailable = $true
        foreach ($e in $script:FreshUninstallVerificationErrors) {
            [void]$issues.Add($e)
        }
    }

    if (Test-Path -LiteralPath $FreshRoot) { [void]$issues.Add("Dossier encore present : $FreshRoot") }

    $tasks = Get-FreshUninstallScheduledTasks
    if ($null -eq $tasks) {
        $unavailable = $true
    }
    else {
        foreach ($t in $tasks) { [void]$issues.Add("Tache encore presente : $($t.TaskName)") }
    }

    foreach ($lnk in @(Get-FreshUninstallDesktopShortcuts)) {
        [void]$issues.Add("Raccourci encore present : $lnk")
    }
    foreach ($d in @(Get-FreshUninstallTempTestDirs)) {
        [void]$issues.Add("Dossier temporaire encore present : $d")
    }
    foreach ($p in @(Get-FreshUninstallTargetProcesses -FreshRoot $FreshRoot)) {
        [void]$issues.Add("Processus encore actif : $($p.ProcessId) $($p.Name)")
    }

    return [pscustomobject]@{
        Issues      = @($issues)
        Unavailable = $unavailable
    }
}

function Get-FreshUninstallReinstallStubContent {
    param([Parameter(Mandatory)][string]$MainUrl)
    return @"
#Requires -RunAsAdministrator
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$launcher = '$MainUrl'
`$self = `$MyInvocation.MyCommand.Path
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
    irm `$launcher | iex
    exit 0
}
catch {
    Write-Host ('Echec relance Fresh Windows (reseau ou acces) : ' + `$_.Exception.Message) -ForegroundColor Red
    Write-Host 'Relance manuelle (copier/coller dans PowerShell admin) :' -ForegroundColor Yellow
    Write-Host ('irm ' + `$launcher + ' | iex') -ForegroundColor Yellow
    exit 3
}
finally {
    if (`$self -and (Test-Path -LiteralPath `$self)) {
        try { Remove-Item -LiteralPath `$self -Force -ErrorAction SilentlyContinue } catch {}
    }
    `$stage = Split-Path -Parent `$self
    if (`$stage -and (Test-Path -LiteralPath `$stage)) {
        try { Remove-Item -LiteralPath `$stage -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}
"@
}

function New-FreshUninstallReinstallStub {
    param([Parameter(Mandatory)][string]$MainUrl)
    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        throw 'TEMP indisponible pour stub relance'
    }
    $stage = Join-Path $tempRoot ("FreshWindows-Reinstall-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $stubPath = Join-Path $stage 'Launch-AfterUninstall.ps1'
    $content = Get-FreshUninstallReinstallStubContent -MainUrl $MainUrl
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
        Write-Host ('Relance manuelle : irm ' + $script:FreshUninstallRepoMainLauncher + ' | iex') -ForegroundColor Yellow
        return $false
    }
}

function Clear-FreshUninstallStagingArtifacts {
    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) { return }
    try {
        Get-ChildItem -LiteralPath $tempRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'FreshWindows-Reinstall-*' } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        Get-ChildItem -LiteralPath $tempRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Uninstall-FreshWindows*.ps1' } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    catch { }
}

function Test-FreshUninstallElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal $id
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Invoke-FreshWindowsUninstall {
    $script:FreshUninstallStepFailures = [System.Collections.ArrayList]@()
    $script:FreshUninstallVerificationErrors = [System.Collections.ArrayList]@()

    if (-not $DryRun -and -not $Confirmed) {
        Write-Host "Annule : confirmation explicite requise (-Confirmed) ou utiliser -DryRun." -ForegroundColor Yellow
        return 2
    }

    if (-not $DryRun -and -not (Test-FreshUninstallElevated)) {
        Write-Host 'Acces refuse : PowerShell administrateur requis pour la suppression.' -ForegroundColor Red
        return 4
    }

    $freshExpected = Join-Path $env:LOCALAPPDATA 'FreshWindows'
    try {
        $freshCanonical = [System.IO.Path]::GetFullPath($freshExpected)
    }
    catch {
        Write-Host "Chemin Fresh Windows invalide." -ForegroundColor Red
        return 1
    }

    $localAppDataRoot = $null
    try { $localAppDataRoot = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA) } catch { }
    if (-not $localAppDataRoot -or -not (Test-FreshUninstallPathUnderRoot -Path $freshCanonical -Root $localAppDataRoot)) {
        Write-Host "Refus : racine Fresh Windows hors LocalAppData attendu." -ForegroundColor Red
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
        Invoke-FreshUninstallDoStep -Label "Arret du processus $($p.ProcessId) ($($p.Name))" -Action {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        } | Out-Null
    }

    $tasksToRemove = $null
    try {
        if (Get-Command Get-ScheduledTask -ErrorAction Stop) {
            $tasksToRemove = @(Get-ScheduledTask -ErrorAction Stop |
                Where-Object { $_.TaskName -like 'FreshWindows-*' -or ($knownTasks -contains $_.TaskName) })
        }
        else {
            throw 'Get-ScheduledTask indisponible'
        }
    }
    catch {
        [void]$script:FreshUninstallVerificationErrors.Add('enumeration taches planifiees impossible')
        if (-not $DryRun) {
            Add-FreshUninstallStepFailure -Label 'Lecture taches planifiees FreshWindows'
        }
        $tasksToRemove = @()
    }

    foreach ($t in $tasksToRemove) {
        Invoke-FreshUninstallDoStep -Label "Suppression de la tache $($t.TaskPath)$($t.TaskName)" -Action {
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
        } | Out-Null
    }

    foreach ($lnk in @(Get-FreshUninstallDesktopShortcuts)) {
        Invoke-FreshUninstallDoStep -Label "Suppression du raccourci $lnk" -Action {
            Remove-Item -LiteralPath $lnk -Force -ErrorAction Stop
        } | Out-Null
    }

    if (Test-Path -LiteralPath $freshCanonical) {
        if (-not $DryRun) { Start-Sleep -Seconds 2 }
        Invoke-FreshUninstallDoStep -Label "Suppression du dossier $freshCanonical" -Action {
            Remove-Item -LiteralPath $freshCanonical -Recurse -Force -ErrorAction Stop
        } | Out-Null
    }

    foreach ($d in @(Get-FreshUninstallTempTestDirs)) {
        Invoke-FreshUninstallDoStep -Label "Suppression du dossier temporaire $d" -Action {
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop
        } | Out-Null
    }

    if (-not $DryRun) {
        Clear-FreshUninstallStagingArtifacts
    }

    Write-Host "`n--- Verification ---"
    if ($DryRun) {
        Write-Host "Simulation terminee, rien n'a ete supprime." -ForegroundColor Yellow
        return 0
    }

    if ($script:FreshUninstallStepFailures.Count -gt 0) {
        Write-Host "Echecs pendant le nettoyage :" -ForegroundColor Red
        $script:FreshUninstallStepFailures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host "Arret : pas de succes ni de relance tant que des etapes ont echoue." -ForegroundColor Red
        return 1
    }

    $verify = Get-FreshUninstallVerification -FreshRoot $freshCanonical
    if ($verify.Unavailable) {
        Write-Host "Verification incomplete (API indisponible) : pas de succes declare." -ForegroundColor Red
        $verify.Issues | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        return 1
    }
    if ($verify.Issues.Count -gt 0) {
        $verify.Issues | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "Nettoyage incomplet : relance ou arret manuel requis." -ForegroundColor Red
        return 1
    }

    Write-Host "Fresh Windows est entierement supprime (cache local / agent / taches)." -ForegroundColor Green

    if ($ReinstallAfter) {
        $stub = New-FreshUninstallReinstallStub -MainUrl $script:FreshUninstallRepoMainLauncher
        $stubParse = $null
        $stubErrs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($stub, [ref]$stubParse, [ref]$stubErrs)
        if ($stubErrs -and $stubErrs.Count -gt 0) {
            Write-Host 'Stub relance invalide (parse) : reinstall annulee.' -ForegroundColor Red
            return 3
        }
        $reinstallOk = Start-FreshUninstallReinstallLauncher -StubPath $stub
        if (-not $reinstallOk) { return 3 }
    }
    else {
        Clear-FreshUninstallStagingArtifacts
    }

    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = Invoke-FreshWindowsUninstall
    exit $exitCode
}
