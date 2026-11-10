#Requires -Version 5.1
<#
  Fonctions partagées Fresh Windows (launcher irm, clone local, tâches planifiées).
  Dot-sourcé depuis launcher.ps1 - utilise $RepoRef, $RepoRawRoot, $LauncherUrl, $FreshAppData du parent.
#>
if (-not $script:FreshWindowsLibEpoch) { $script:FreshWindowsLibEpoch = 60 }

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

function Remove-FreshWindowsObsoleteLocalAssets {
    <#
      Nettoie sous FreshAppData uniquement les artefacts agent/IA/voix obsoletes.
      Ne touche pas aux installs tierces (CyberScribe, Ollama) hors ce dossier.
    #>
    param([Parameter(Mandatory)][string]$FreshAppData)

    if (-not (Test-Path -LiteralPath $FreshAppData)) { return $true }

    $relFiles = @(
        'GameMode-WatchAgent.ps1',
        'Stop-FreshWatchAgent.ps1',
        'Launch-GameModeWatch.ps1',
        'Start-WatchAgent.cmd',
        'Register-WatchAgentTask.ps1',
        'Register-WatchAgentTask.cmd',
        'watch-agent-user.json',
        'watch-agent.log',
        'agent-ai.user.json',
        'skills-apps.user.json',
        'skills-web.user.json',
        'inventory.json',
        'game-session.state.json',
        'ai-history.jsonl',
        'ai-prompt.pending.txt',
        'weekly-health-last.json',
        'repo.root'
    )
    foreach ($rel in $relFiles) {
        $p = Join-Path $FreshAppData $rel
        if (Test-Path -LiteralPath $p) {
            try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop } catch { }
        }
    }

    $relDirs = @('ai', 'bin', 'configs\skills')
    foreach ($rel in $relDirs) {
        $p = Join-Path $FreshAppData $rel
        if (Test-Path -LiteralPath $p) {
            try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop } catch { }
        }
    }

    $libDir = Join-Path $FreshAppData 'lib'
    if (Test-Path -LiteralPath $libDir) {
        Get-ChildItem -LiteralPath $libDir -Filter 'FreshAgent-*.ps1' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { }
            }
    }

    $cfgDir = Join-Path $FreshAppData 'configs'
    if (Test-Path -LiteralPath $cfgDir) {
        foreach ($pattern in @('agent-*.json', 'skills-*.json', 'services-allowlist.json')) {
            Get-ChildItem -LiteralPath $cfgDir -Filter $pattern -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch { }
                }
        }
    }

    try {
        if (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName 'FreshWindows-WatchAgent' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            & "$env:SystemRoot\System32\schtasks.exe" /Delete /TN 'FreshWindows-WatchAgent' /F 2>&1 | Out-Null
        }
    }
    catch { }

    $startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Fresh Windows Surveillance.lnk'
    if (Test-Path -LiteralPath $startupLnk) {
        try { Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue } catch { }
    }

    return $true
}

function Test-FreshWindowsIsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal $id
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
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

    Remove-FreshWindowsObsoleteLocalAssets -FreshAppData $FreshAppData | Out-Null

    foreach ($scriptName in @('GameMode-Common.ps1', 'Invoke-GameModeKill.ps1', 'Sync-FreshWindowsAgent.ps1', 'Invoke-FreshWindowsBackgroundAudit.ps1')) {
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

    $bloatLib = Join-Path $FreshAppData 'lib\FreshWindows-AppxBloatware.ps1'
    $libDir = Split-Path $bloatLib -Parent
    if (-not (Test-Path -LiteralPath $libDir)) { New-Item -ItemType Directory -Path $libDir -Force | Out-Null }
    try {
        Invoke-WebRequest -Uri "$RepoRawRoot/scripts/lib/FreshWindows-AppxBloatware.ps1" -OutFile $bloatLib -UseBasicParsing
    }
    catch { }

    Set-Content -LiteralPath (Join-Path $FreshAppData 'scripts.ref') -Value $Ref -Encoding UTF8 -NoNewline
    Write-FreshWindowsScriptsStamp -FreshAppData $FreshAppData | Out-Null

    Publish-FreshGameModeKillStub -FreshAppData $FreshAppData | Out-Null
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
    Write-Host 'Conserve : apps winget, tweaks WinUtil/ShutUp10, CyberScribe et modeles externes.' -ForegroundColor DarkGray
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
        Write-Host 'Ne retire pas les apps winget, CyberScribe, ni les modeles vocaux externes.' -ForegroundColor DarkGray
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
