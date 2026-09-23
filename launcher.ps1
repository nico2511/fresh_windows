#Requires -RunAsAdministrator
# ============================================================
#  Fresh Windows - toolbox reinstall / maintenance
#  Configs lues depuis GitHub (édition à distance)
#
#  Modes non interactifs :
#    $env:FRESH_WIN_MODE='full'; irm ... | iex
#    Apps : standard | gaming | dev | custom | custom:<nom> | full
#    WinUtil : winutil-oneclick | winutil-standard | winutil-minimal |
#              winutil-advanced | winutil-appx | maintenance
#    Autre : tasks | game-mode | game-mode-shortcuts | game-mode-watch |
#            powertoys-profile | shutup10 | brave-optimize | brave-debloat | betterzen
#
#  Pin de version (commit / tag / branche) :
#    $env:FRESH_WIN_REF='abc1234'
#    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm .../$env:FRESH_WIN_REF/launcher.ps1 | iex"
#
#  Premier lancement (ExecutionPolicy) :
#    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm .../launcher.ps1 | iex"
#    Le launcher pose RemoteSigned (CurrentUser) + Unblock-File sur le cache AppData.
# ============================================================

# Via env (compatible irm | iex) - pas de param() qui casse le pipe
$Mode = if ($env:FRESH_WIN_MODE) { $env:FRESH_WIN_MODE.Trim().ToLowerInvariant() } else { 'menu' }
$RepoRef = if ($env:FRESH_WIN_REF -and $env:FRESH_WIN_REF.Trim()) {
    $env:FRESH_WIN_REF.Trim()
} else {
    'main'
}

# Stop = les échecs remontent (try/catch locaux pour les cas attendus)
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Fresh Windows"

# TLS 1.2 requis sur certaines machines / vieux PowerShell
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Configs : builtins sur GitHub + paquets custom (repo et/ou AppData local)
$RepoSlug = "nico2511/fresh_windows"
$RepoRawRoot = "https://raw.githubusercontent.com/$RepoSlug/$RepoRef"
$RepoBlobRoot = "https://github.com/$RepoSlug/blob/$RepoRef"
$BaseUrl = "$RepoRawRoot/configs"
$GuidesBaseUrl = "$RepoBlobRoot/guides"
$LauncherUrl = "$RepoRawRoot/launcher.ps1"
$IconUrl = "$RepoRawRoot/assets/fresh-windows.ico"
$FreshAppData = Join-Path $env:LOCALAPPDATA "FreshWindows"
$CustomAppsLocalDir = Join-Path $FreshAppData "apps-custom"
$script:FreshBrand = "Fresh Windows"
# Incrémenter quand les libs changent alors que FRESH_WIN_REF reste "main" (sinon cache périmé)
$script:FreshWindowsLibEpoch = 35

function Ensure-FreshWindowsExecutionPolicy {
    <#
      Debloque ExecutionPolicy pour scripts locaux / cache AppData.
      Process = Bypass (session). CurrentUser = RemoteSigned si trop strict.
      Unblock-File retire la zone Internet (ADS) sur les .ps1 telecharges.
    #>
    $changed = $false

    try {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
    } catch { }

    $restrictive = @('Restricted', 'AllSigned')
    try {
        $currentUser = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
        $effective = Get-ExecutionPolicy -ErrorAction SilentlyContinue
        $needsUser = ($currentUser -in $restrictive) -or (
            ($currentUser -eq 'Undefined' -or [string]::IsNullOrWhiteSpace([string]$currentUser)) -and
            ($effective -in $restrictive)
        )
        if ($needsUser) {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
            $changed = $true
            Write-Host "ExecutionPolicy CurrentUser → RemoteSigned (scripts locaux autorises)." -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "ExecutionPolicy CurrentUser non modifiable : $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    try {
        New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
        Get-ChildItem -LiteralPath $FreshAppData -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch { }
            }
    } catch { }

    return $changed
}

Ensure-FreshWindowsExecutionPolicy | Out-Null

function ConvertTo-Utf8BomFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return
    }
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    [IO.File]::WriteAllText($Path, $text, $utf8Bom)
}

function Get-FreshWindowsBootstrapScriptPath {
    param(
        [Parameter(Mandatory)][string]$CacheFileName,
        [Parameter(Mandatory)][string]$RemotePath
    )

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $dest = Join-Path $FreshAppData $CacheFileName
    $meta = Join-Path $FreshAppData "$CacheFileName.ref"
    $url  = "$RepoRawRoot/$RemotePath"
    $cacheToken = "$RepoRef|$script:FreshWindowsLibEpoch"
    $needFetch = -not (Test-Path -LiteralPath $dest)
    if (-not $needFetch -and (Test-Path -LiteralPath $meta)) {
        try {
            if ((Get-Content -LiteralPath $meta -Raw -Encoding UTF8).Trim() -ne $cacheToken) {
                $needFetch = $true
            }
        }
        catch { $needFetch = $true }
    }
    elseif (-not (Test-Path -LiteralPath $meta)) { $needFetch = $true }

    if ($needFetch) {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Set-Content -LiteralPath $meta -Value $cacheToken -Encoding UTF8 -NoNewline
    }
    ConvertTo-Utf8BomFile -Path $dest
    try { Unblock-File -LiteralPath $dest -ErrorAction SilentlyContinue } catch { }
    return $dest
}

function Get-FreshWindowsLibraryPaths {
    $script:FreshWindowsLibFiles = @(
        'Import-CachedScript.ps1',
        'Launcher-Core.ps1',
        'Launcher-WinUtil.ps1',
        'Launcher-Tasks.ps1',
        'Launcher-GpuMenus.ps1'
    )

    # irm | iex : $PSScriptRoot est vide - Join-Path echoue si on l'appelle quand meme
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $libRoot = Join-Path $PSScriptRoot 'scripts/lib'
        $allLocal = $true
        $local = @()
        foreach ($name in $script:FreshWindowsLibFiles) {
            $p = Join-Path $libRoot $name
            if (-not (Test-Path -LiteralPath $p)) {
                $allLocal = $false
                break
            }
            $local += $p
        }
        if ($allLocal) { return $local }
    }

    $paths = @()
    foreach ($name in $script:FreshWindowsLibFiles) {
        $p = Get-FreshWindowsBootstrapScriptPath `
            -CacheFileName $name `
            -RemotePath "scripts/lib/$name"
        ConvertTo-Utf8BomFile -Path $p
        $paths += $p
    }
    return $paths
}

# Dot-source AU NIVEAU SCRIPT (pas dans une fonction) sinon Wait-ForUser etc. disparaissent au return.
try {
    $libPaths = @(Get-FreshWindowsLibraryPaths)
    if ($libPaths.Count -lt 1) { throw 'Liste de bibliotheques vide.' }
    foreach ($libPath in $libPaths) {
        ConvertTo-Utf8BomFile -Path $libPath
        . $libPath
    }

    # Cache "main" sans epoch = libs d'avant le merge : forcer un re-telechargement
    if (-not (Get-Command Register-FreshWindowsWatchAgentLogon -ErrorAction SilentlyContinue)) {
        Write-Host "Cache libs obsolete -> re-telechargement force..." -ForegroundColor Yellow
        $libPaths = @()
        foreach ($name in $script:FreshWindowsLibFiles) {
            $dest = Join-Path $FreshAppData $name
            $meta = Join-Path $FreshAppData "$name.ref"
            $url  = "$RepoRawRoot/scripts/lib/$name"
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            Set-Content -LiteralPath $meta -Value "$RepoRef|$script:FreshWindowsLibEpoch" -Encoding UTF8 -NoNewline
            ConvertTo-Utf8BomFile -Path $dest
            . $dest
            $libPaths += $dest
        }
    }

    $gmRel = 'scripts/GameMode-Common.ps1'
    $gmPath = $null
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $candidate = Join-Path $PSScriptRoot $gmRel
        if (Test-Path -LiteralPath $candidate) { $gmPath = $candidate }
    }
    if (-not $gmPath) {
        $gmPath = Get-FreshWindowsBootstrapScriptPath `
            -CacheFileName 'GameMode-Common.ps1' `
            -RemotePath $gmRel
        ConvertTo-Utf8BomFile -Path $gmPath
    }
    # Common aussi : re-fetch si Start-FreshWindowsPowerShell trop vieux / absent
    if (-not (Get-Command Start-FreshWindowsPowerShell -ErrorAction SilentlyContinue)) {
        $gmPath = Join-Path $FreshAppData 'GameMode-Common.ps1'
        Invoke-WebRequest -Uri "$RepoRawRoot/$gmRel" -OutFile $gmPath -UseBasicParsing
        ConvertTo-Utf8BomFile -Path $gmPath
    }
    . $gmPath -RepoRef $RepoRef
}
catch {
    Write-Host "Bibliotheques Fresh Windows indisponibles : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Impossible de charger scripts/lib (reseau ou repo). Arret." -ForegroundColor Red
    exit 1
}

# Toujours definir ici (irm | iex) : independant du cache Core CDN
function Test-FreshWindowsIsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal $id
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Register-FreshWindowsWatchAgentLogon {
    param(
        [Parameter(Mandatory)][string]$FreshAppData
    )

    $taskName = 'FreshWindows-WatchAgent'
    $cmdPath = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
    if (-not (Test-Path -LiteralPath $cmdPath)) {
        throw "Start-WatchAgent.cmd introuvable."
    }

    # Deja presente et pointe vers le .cmd -> OK (evite Acces refuse en admin sur -Force)
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
Register-ScheduledTask -TaskName `$taskName -Action `$action -Trigger `$trigger -Principal `$principal -Settings `$settings -Description 'Fresh Windows agent tray (Limited).' -Force | Out-Null
"@ | Set-Content -LiteralPath $helperPs1 -Encoding UTF8

    @"
@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Register-WatchAgentTask.ps1"
"@ | Set-Content -LiteralPath $helperCmd -Encoding ASCII

    if (-not (Test-FreshWindowsIsElevated)) {
        & $helperPs1
        return $taskName
    }

    # Admin : Limited refuse souvent Register-ScheduledTask -Force -> enfant sans elevation
    Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" `
        -ArgumentList "/trustlevel:0x20000 `"$helperCmd`"" `
        -Wait -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 800

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        return $taskName
    }

    $null = & "$env:SystemRoot\System32\schtasks.exe" /Delete /TN $taskName /F 2>&1
    $create = & "$env:SystemRoot\System32\schtasks.exe" /Create /TN $taskName /TR "`"$cmdPath`"" /SC ONLOGON /RL LIMITED /F 2>&1
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        return $taskName
    }

    throw ("Acces refuse pour la tache Limited. Startup .lnk reste actif. Detail: {0}" -f ($create | Out-String).Trim())
}

function Install-FullSetup {
    param([switch]$NoPause)

    $a = [bool](Install-FromJson -FileName "apps-standard.json" -Category "Standard" -NoPause)
    $b = [bool](Install-FromJson -FileName "apps-gaming.json" -Category "Gaming" -NoPause)
    $c = [bool](Install-FromJson -FileName "apps-dev.json" -Category "Dev" -NoPause)
    $ok = $a -and $b -and $c
    if ($ok) {
        Write-Host "`nFull Setup terminé !" -ForegroundColor Green
    }
    else {
        Write-Host "`nFull Setup terminé avec des échecs (détail ci-dessus)." -ForegroundColor Red
    }
    if (-not $NoPause) { Wait-ForUser }
    return $ok
}

function Get-Config {
    param(
        [string]$FileName,
        [string]$LocalPath
    )
    try {
        if ($LocalPath) {
            if (-not (Test-Path -LiteralPath $LocalPath)) {
                throw "Fichier local introuvable : $LocalPath"
            }
            $raw = Get-Content -LiteralPath $LocalPath -Raw -Encoding UTF8
            $json = $raw | ConvertFrom-Json
        }
        else {
            $url  = "$BaseUrl/$FileName"
            $json = Invoke-RestMethod -Uri $url -UseBasicParsing
        }
        if ($null -eq $json) {
            throw "Config vide ou invalide."
        }
        return @($json)
    }
    catch {
        $label = if ($LocalPath) { $LocalPath } else { $FileName }
        Write-Host "Erreur lors du chargement de $label" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        return $null
    }
}

function Get-ConfigObject {
    param([string]$FileName)
    try {
        $url  = "$BaseUrl/$FileName"
        $json = Invoke-RestMethod -Uri $url -UseBasicParsing
        if ($null -eq $json) {
            throw "Config vide ou invalide."
        }
        return $json
    }
    catch {
        Write-Host "Erreur lors du téléchargement de $FileName" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        return $null
    }
}

function Show-InstallProgress {
    param(
        [int]$Current,
        [int]$Total,
        [string]$App,
        [string]$Category
    )
    $pct    = if ($Total -gt 0) { [math]::Round(($Current / $Total) * 100) } else { 0 }
    $width  = 28
    $filled = [math]::Round(($pct / 100) * $width)
    $bar    = ('#' * $filled) + ('-' * ($width - $filled))

    Write-Progress -Activity "Installation : $Category" -Status "$Current / $Total - $App" -PercentComplete $pct
    Write-Host ("  [{0}] {1,3}%  ({2}/{3})  {4}" -f $bar, $pct, $Current, $Total, $App) -ForegroundColor DarkCyan
    try { $Host.UI.RawUI.WindowTitle = "Fresh Windows [$Current/$Total] $Category - $App" } catch { }
}

function Get-AppLabel {
    param($App)
    if ($App -is [string]) { return $App }
    if ($App.name) { return [string]$App.name }
    if ($App.url) { return [string]$App.url }
    return "$App"
}

function Install-GitHubDownload {
    param($App)

    $name     = if ($App.name) { [string]$App.name } else { "download" }
    $url      = [string]$App.url
    $fileName = if ($App.fileName) { [string]$App.fileName } else { Split-Path $url -Leaf }
    $destDir  = if ($App.destDir) {
        [Environment]::ExpandEnvironmentVariables([string]$App.destDir)
    } else {
        Join-Path $env:LOCALAPPDATA "Programs\$name"
    }
    $isArchive = ($App.archive -eq $true) -or ($fileName -match '\.zip$')
    $destPath = Join-Path $destDir $fileName

    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-Host "    URL manquante pour $name" -ForegroundColor Red
        return $false
    }

    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Write-Host "    Téléchargement → $destPath" -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing
    }
    catch {
        Write-Host "    Échec téléchargement : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path -LiteralPath $destPath)) {
        Write-Host "    Fichier introuvable après téléchargement." -ForegroundColor Red
        return $false
    }

    $shortcutTarget = $destPath
    if ($isArchive) {
        Write-Host "    Extraction archive..." -ForegroundColor DarkGray
        try {
            Expand-Archive -LiteralPath $destPath -DestinationPath $destDir -Force
            Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "    Échec extraction : $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }

        $exeName = if ($App.shortcutExe) { [string]$App.shortcutExe } else { "$name.exe" }
        $found = Get-ChildItem -LiteralPath $destDir -Recurse -Filter $exeName -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $found) {
            $found = Get-ChildItem -LiteralPath $destDir -Recurse -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '(?i)(unins|setup|update|crash)' } |
                Select-Object -First 1
        }
        if ($found) {
            $shortcutTarget = $found.FullName
            Write-Host "    Exe : $shortcutTarget" -ForegroundColor DarkGray
        }
        else {
            Write-Host "    Archive extraite mais exe introuvable pour le raccourci." -ForegroundColor DarkYellow
            $shortcutTarget = $null
        }
    }

    if ($App.shortcut -eq $true -and $shortcutTarget) {
        try {
            $programs = [Environment]::GetFolderPath('Programs')
            $lnkPath  = Join-Path $programs "$name.lnk"
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut($lnkPath)
            $lnk.TargetPath = $shortcutTarget
            $lnk.WorkingDirectory = (Split-Path -Parent $shortcutTarget)
            $lnk.Description = $name
            $lnk.Save()
            Write-Host "    Raccourci menu Démarrer créé." -ForegroundColor DarkGray
        }
        catch {
            Write-Host "    Raccourci non créé : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    return $true
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory)][string]$Id)

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = winget list -e --id $Id --disable-interactivity 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { return $false }
        # Ligne de résultat contient l'ID (évite faux positifs sur l'en-tête)
        return ($output -match [regex]::Escape($Id))
    }
    catch {
        return $false
    }
    finally {
        $ErrorActionPreference = $prevEap
    }
}

function Install-AppEntry {
    param($App)

    if ($App -is [string]) {
        if (Test-WingetPackageInstalled -Id $App) {
            Write-Host "    déjà présent (winget) - skip" -ForegroundColor Green
            return $true
        }

        winget install -e --id $App --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
        # 0 = OK, -1978335189 (0x8A15002B) = déjà installé
        $ok = ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189)
        if ($ok -and $App -eq 'Microsoft.PowerToys') {
            Start-Sleep -Seconds 2
            Apply-PowerToysProfile | Out-Null
        }
        if ($ok -and $App -eq 'OO-Software.ShutUp10') {
            Start-Sleep -Seconds 1
            Invoke-ShutUp10Recommended -LaunchGui | Out-Null
        }
        if ($ok -and $App -eq 'Brave.Brave') {
            Start-Sleep -Seconds 1
            Invoke-BraveOptimize -NoPause | Out-Null
        }
        if ($ok -and $App -eq 'Zen-Team.Zen-Browser') {
            Start-Sleep -Seconds 2
            Invoke-BetterZen -EnsureProfile -NoPause | Out-Null
        }
        if ($ok -and $App -eq 'voidtools.Everything') {
            Start-Sleep -Seconds 1
            Disable-EverythingAutostart | Out-Null
        }
        return $ok
    }

    if ($App.url) {
        return (Install-GitHubDownload -App $App)
    }

    Write-Host "    Entrée non reconnue (attendu: winget id ou objet url)." -ForegroundColor Red
    return $false
}

function Apply-PowerToysProfile {
    Write-Host "  → Application du profil PowerToys..." -ForegroundColor Gray
    $profile = Get-ConfigObject -FileName "powertoys-profile.json"
    if (-not $profile) {
        Write-Host "    Profil PowerToys introuvable sur GitHub." -ForegroundColor Red
        return $false
    }

    $settingsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\settings.json"
    $dir = Split-Path $settingsPath -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    # Stopper PowerToys pour écrire settings.json proprement
    Get-Process -Name "PowerToys*","PowerToys.Settings" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800

    $settings = $null
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            $settings = $null
        }
    }
    if (-not $settings) {
        $settings = [pscustomobject]@{
            startup = $true
            enabled = [pscustomobject]@{}
        }
    }

    if ($null -ne $profile.startup) {
        $settings | Add-Member -NotePropertyName startup -NotePropertyValue ([bool]$profile.startup) -Force
    }

    if (-not $settings.enabled) {
        $settings | Add-Member -NotePropertyName enabled -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    if ($profile.enabled) {
        foreach ($prop in $profile.enabled.PSObject.Properties) {
            $settings.enabled | Add-Member -NotePropertyName $prop.Name -NotePropertyValue ([bool]$prop.Value) -Force
        }
    }

    $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

    # Relancer PowerToys si installé
    $ptCandidates = @(
        "$env:LOCALAPPDATA\PowerToys\PowerToys.exe",
        "$env:ProgramFiles\PowerToys\PowerToys.exe"
    )
    foreach ($exe in $ptCandidates) {
        if (Test-Path -LiteralPath $exe) {
            Start-Process -FilePath $exe | Out-Null
            break
        }
    }

    Write-Host "    Profil PowerToys écrit : $settingsPath" -ForegroundColor DarkGray
    return $true
}

function Install-FromJson {
    param(
        [string]$FileName,
        [string]$LocalPath,
        [string]$Category,
        [switch]$NoPause
    )
    $apps = if ($LocalPath) {
        Get-Config -LocalPath $LocalPath
    } else {
        Get-Config -FileName $FileName
    }
    if (-not $apps) {
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }

    $apps = @(
        $apps | Where-Object {
            if ($_ -is [string]) { -not [string]::IsNullOrWhiteSpace($_) }
            else { $true }
        }
    )
    $total = $apps.Count
    $index = 0
    $failed = @()

    Write-Host "`n→ Installation de la catégorie : $Category ($total apps)" -ForegroundColor Yellow

    foreach ($app in $apps) {
        $index++
        $label = Get-AppLabel -App $app
        Show-InstallProgress -Current $index -Total $total -App $label -Category $Category
        if (-not (Install-AppEntry -App $app)) {
            Write-Host "    Échec : $label" -ForegroundColor Red
            $failed += $label
        }
    }

    Write-Progress -Activity "Installation : $Category" -Completed
    try { $Host.UI.RawUI.WindowTitle = $script:FreshBrand } catch { }

    if ($failed.Count -gt 0) {
        Write-Host "`nÉchecs ($Category) : $($failed -join ', ')" -ForegroundColor Red
        Write-Host "  ($($failed.Count)/$total en échec - codes winget / réseau non ignorés)" -ForegroundColor DarkYellow
    }
    else {
        Write-Host "`nCatégorie $Category terminée. [$total/$total]" -ForegroundColor Green
    }

    if (-not $NoPause) { Wait-ForUser }
    return ($failed.Count -eq 0)
}

function Get-CustomAppsRepoDir {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { return $null }
    $dir = Join-Path $PSScriptRoot 'configs/apps-custom'
    if (Test-Path -LiteralPath $dir) { return $dir }
    return $null
}

function Add-CustomAppPackCandidate {
    param(
        [Parameter(Mandatory)]$PackMap,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('local', 'repo', 'github')][string]$Source,
        [string]$LocalPath,
        [string]$RemoteFileName
    )

    $key = $Name.ToLowerInvariant()
    if ($PackMap.ContainsKey($key)) {
        # Priorité : local AppData > clone repo > GitHub
        $rank = @{ local = 3; repo = 2; github = 1 }
        $existing = $PackMap[$key]
        if ($rank[$Source] -le $rank[$existing.Source]) { return }
    }

    $PackMap[$key] = [pscustomobject]@{
        Name           = $Name
        Source         = $Source
        LocalPath      = $LocalPath
        RemoteFileName = $RemoteFileName
    }
}

function Get-CustomAppPacks {
    $map = @{}

    New-Item -ItemType Directory -Path $CustomAppsLocalDir -Force | Out-Null
    Get-ChildItem -LiteralPath $CustomAppsLocalDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            Add-CustomAppPackCandidate -PackMap $map -Name $_.BaseName -Source local -LocalPath $_.FullName
        }

    $repoDir = Get-CustomAppsRepoDir
    if ($repoDir) {
        Get-ChildItem -LiteralPath $repoDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                Add-CustomAppPackCandidate -PackMap $map -Name $_.BaseName -Source repo -LocalPath $_.FullName
            }
    }

    try {
        $apiUrl = "https://api.github.com/repos/$RepoSlug/contents/configs/apps-custom?ref=$([uri]::EscapeDataString($RepoRef))"
        $headers = @{
            'User-Agent' = 'FreshWindows'
            'Accept'     = 'application/vnd.github+json'
        }
        $remote = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing
        foreach ($item in @($remote)) {
            if ($item.type -ne 'file') { continue }
            $fileName = [string]$item.name
            if ($fileName -notmatch '\.json$') { continue }
            $packName = [IO.Path]::GetFileNameWithoutExtension($fileName)
            Add-CustomAppPackCandidate `
                -PackMap $map `
                -Name $packName `
                -Source github `
                -RemoteFileName ("apps-custom/{0}" -f $fileName)
        }
    }
    catch {
        Write-Host "Liste GitHub apps-custom indisponible : $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    return @($map.Values | Sort-Object Name)
}

function Install-CustomAppPack {
    param(
        [Parameter(Mandatory)]$Pack,
        [switch]$NoPause
    )

    $category = "Custom: $($Pack.Name)"
    if ($Pack.LocalPath) {
        return [bool](Install-FromJson -LocalPath $Pack.LocalPath -Category $category -NoPause:$NoPause)
    }
    if ($Pack.RemoteFileName) {
        return [bool](Install-FromJson -FileName $Pack.RemoteFileName -Category $category -NoPause:$NoPause)
    }
    Write-Host "Paquet custom invalide : $($Pack.Name)" -ForegroundColor Red
    if (-not $NoPause) { Wait-ForUser }
    return $false
}

function Install-AllCustomAppPacks {
    param([switch]$NoPause)

    $packs = @(Get-CustomAppPacks)
    if ($packs.Count -eq 0) {
        Write-Host "Aucun paquet custom trouvé." -ForegroundColor Yellow
        Write-Host "  Repo  : configs/apps-custom/*.json" -ForegroundColor DarkGray
        Write-Host "  Local : $CustomAppsLocalDir" -ForegroundColor DarkGray
        Write-Host "  IDs   : https://winstall.app" -ForegroundColor DarkGray
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }

    $ok = $true
    foreach ($pack in $packs) {
        if (-not (Install-CustomAppPack -Pack $pack -NoPause)) {
            $ok = $false
        }
    }
    if (-not $NoPause) { Wait-ForUser }
    return $ok
}

function Install-CustomAppPackByName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$NoPause
    )

    $packs = @(Get-CustomAppPacks)
    $match = $packs | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $match) {
        $match = $packs | Where-Object { $_.Name -eq $Name -or $_.Name.ToLowerInvariant() -eq $Name.ToLowerInvariant() } |
            Select-Object -First 1
    }
    if (-not $match) {
        Write-Host "Paquet custom introuvable : $Name" -ForegroundColor Red
        if ($packs.Count -gt 0) {
            Write-Host ("Disponibles : {0}" -f (($packs | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor DarkGray
        }
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }
    return (Install-CustomAppPack -Pack $match -NoPause:$NoPause)
}

function Open-CustomAppsMenu {
    do {
        Clear-Host
        Write-Host "=== APPS CUSTOM ===" -ForegroundColor Cyan
        Write-Host "Dossier local : $CustomAppsLocalDir" -ForegroundColor DarkGray
        Write-Host "IDs winget    : https://winstall.app" -ForegroundColor DarkGray
        Write-Host ""

        $packs = @(Get-CustomAppPacks)
        if ($packs.Count -eq 0) {
            Write-Host "Aucun fichier *.json détecté." -ForegroundColor Yellow
            Write-Host "Ajoute un paquet dans configs/apps-custom/ (fork) ou dans le dossier local." -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "1. Ouvrir le dossier local" -ForegroundColor Yellow
            Write-Host "2. Ouvrir winstall.app" -ForegroundColor White
            Write-Host "3. Retour" -ForegroundColor Gray
            $c = Read-Host "Choix"
            switch ($c) {
                "1" {
                    New-Item -ItemType Directory -Path $CustomAppsLocalDir -Force | Out-Null
                    Start-Process explorer.exe $CustomAppsLocalDir
                }
                "2" { Start-Process "https://winstall.app" }
                "3" { return }
                default {
                    Write-Host "Choix invalide" -ForegroundColor Red
                    Start-Sleep 1
                }
            }
            continue
        }

        $i = 1
        foreach ($pack in $packs) {
            $srcLabel = switch ($pack.Source) {
                'local'  { 'local' }
                'repo'   { 'repo' }
                'github' { 'github' }
                default  { $pack.Source }
            }
            Write-Host (" {0,2}  {1}  [{2}]" -f $i, $pack.Name, $srcLabel) -ForegroundColor Green
            $i++
        }
        Write-Host (" {0,2}  Installer tous les paquets custom" -f $i) -ForegroundColor Cyan
        $allChoice = $i
        $i++
        Write-Host (" {0,2}  Ouvrir le dossier local" -f $i) -ForegroundColor Yellow
        $openDirChoice = $i
        $i++
        Write-Host (" {0,2}  Ouvrir winstall.app" -f $i) -ForegroundColor White
        $winstallChoice = $i
        $i++
        Write-Host (" {0,2}  Retour" -f $i) -ForegroundColor Gray
        $backChoice = $i
        Write-Host ""
        $c = Read-Host "Choix"

        if ($c -match '^\d+$') {
            $n = [int]$c
            if ($n -ge 1 -and $n -le $packs.Count) {
                Install-CustomAppPack -Pack $packs[$n - 1] | Out-Null
                continue
            }
            if ($n -eq $allChoice) {
                Install-AllCustomAppPacks | Out-Null
                continue
            }
            if ($n -eq $openDirChoice) {
                New-Item -ItemType Directory -Path $CustomAppsLocalDir -Force | Out-Null
                Start-Process explorer.exe $CustomAppsLocalDir
                continue
            }
            if ($n -eq $winstallChoice) {
                Start-Process "https://winstall.app"
                continue
            }
            if ($n -eq $backChoice) { return }
        }
        Write-Host "Choix invalide" -ForegroundColor Red
        Start-Sleep 1
    } while ($true)
}

function Disable-EverythingAutostart {
    Write-Host "  → Everything : désactivation service + démarrage auto..." -ForegroundColor Gray
    $ok = $true
    try {
        $svc = Get-Service -Name 'Everything' -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -ne 'Stopped') {
                Stop-Service -Name 'Everything' -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name 'Everything' -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "    Service Everything désactivé." -ForegroundColor DarkGray
        }
        else {
            Write-Host "    Service Everything absent (OK)." -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "    Service : $($_.Exception.Message)" -ForegroundColor DarkYellow
        $ok = $false
    }

    # Run keys
    foreach ($runKey in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )) {
        try {
            if (Test-Path -LiteralPath $runKey) {
                $props = Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Name -match '(?i)Everything' -or [string]$p.Value -match '(?i)Everything\.exe') {
                        Remove-ItemProperty -LiteralPath $runKey -Name $p.Name -ErrorAction SilentlyContinue
                        Write-Host "    Run retiré : $($p.Name)" -ForegroundColor DarkGray
                    }
                }
            }
        } catch { }
    }

    # Startup folder shortcuts
    try {
        $startup = [Environment]::GetFolderPath('Startup')
        Get-ChildItem -LiteralPath $startup -Filter '*Everything*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                Write-Host "    Startup retiré : $($_.Name)" -ForegroundColor DarkGray
            }
    } catch { }

    # Prefer Everything.ini run_on_* = 0 if present
    $iniCandidates = @(
        (Join-Path $env:APPDATA 'Everything\Everything.ini'),
        (Join-Path $env:ProgramFiles 'Everything\Everything.ini')
    )
    if (${env:ProgramFiles(x86)}) {
        $iniCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Everything\Everything.ini')
    }
    foreach ($ini in $iniCandidates) {
        if (-not (Test-Path -LiteralPath $ini)) { continue }
        try {
            $raw = Get-Content -LiteralPath $ini -Raw -Encoding UTF8
            $new = $raw
            foreach ($key in @('run_on_system_startup', 'run_on_startup', 'run_as_service')) {
                if ($new -match "(?im)^$key=") {
                    $new = [regex]::Replace($new, "(?im)^$key=.*$", "$key=0")
                }
                else {
                    $new = $new.TrimEnd() + "`r`n$key=0`r`n"
                }
            }
            if ($new -ne $raw) {
                Set-Content -LiteralPath $ini -Value $new -Encoding UTF8
                Write-Host "    INI mis à jour : $ini" -ForegroundColor DarkGray
            }
        } catch { }
    }

    return $ok
}

function Invoke-BraveOptimize {
    param(
        [switch]$Remove,
        [switch]$NoPause
    )

    $cfg = Get-ConfigObject -FileName 'brave-optimize.json'
    $regPath = if ($cfg -and $cfg.registryPath) {
        [string]$cfg.registryPath
    } else {
        'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
    }

    if ($Remove) {
        Write-Host "`n→ Retrait profil Brave (policies Fresh)..." -ForegroundColor Yellow
        try {
            if (Test-Path -LiteralPath $regPath) {
                Remove-Item -LiteralPath $regPath -Recurse -Force -ErrorAction Stop
                Write-Host "  Policies supprimées : $regPath" -ForegroundColor Green
                Write-Host "  Relance Brave pour prendre effet." -ForegroundColor DarkGray
            }
            else {
                Write-Host "  Aucune policy Fresh présente." -ForegroundColor DarkGray
            }
            if (-not $NoPause) { Wait-ForUser }
            return $true
        }
        catch {
            Write-Host "  Échec retrait : $($_.Exception.Message)" -ForegroundColor Red
            if (-not $NoPause) { Wait-ForUser }
            return $false
        }
    }

    Write-Host "`n→ Profil Brave Fresh (policies curatées)..." -ForegroundColor Cyan
    if (-not $cfg -or -not $cfg.disable) {
        Write-Host "  brave-optimize.json introuvable." -ForegroundColor Red
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }

    try {
        New-Item -Path $regPath -Force | Out-Null
        foreach ($prop in $cfg.disable.PSObject.Properties) {
            $name = $prop.Name
            $val = [int]$prop.Value
            New-ItemProperty -Path $regPath -Name $name -PropertyType DWord -Value $val -Force | Out-Null
            Write-Host ("    {0} = {1}" -f $name, $val) -ForegroundColor DarkGray
        }
        Write-Host "  Policies écrites (Rewards/Wallet/VPN/Leo/News/Talk/télémétrie off ; Sync/Tor gardés)." -ForegroundColor Green
        Write-Host "  Relance Brave si déjà ouvert. Vérif : brave://policy" -ForegroundColor DarkGray
        if (-not $NoPause) { Wait-ForUser }
        return $true
    }
    catch {
        Write-Host "  Échec policies Brave : $($_.Exception.Message)" -ForegroundColor Red
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }
}

function Initialize-ZenDefaultProfile {
    $zenRoot = Join-Path $env:APPDATA 'zen'
    $profilesRoot = Join-Path $zenRoot 'Profiles'
    $profileDir = Join-Path $profilesRoot 'fresh.default'
    $iniPath = Join-Path $zenRoot 'profiles.ini'

    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

    if (-not (Test-Path -LiteralPath $iniPath)) {
        @"
[General]
StartWithLastProfile=1
Version=2

[Profile0]
Name=fresh
IsRelative=1
Path=Profiles/fresh.default
Default=1
"@ | Set-Content -LiteralPath $iniPath -Encoding UTF8
        Write-Host "  Profil Zen créé : $profileDir" -ForegroundColor DarkGray
    }

    return $profileDir
}

function Get-ZenDefaultProfilePath {
    $zenRoot = Join-Path $env:APPDATA 'zen'
    $iniPath = Join-Path $zenRoot 'profiles.ini'
    if (-not (Test-Path -LiteralPath $iniPath)) {
        return $null
    }

    $lines = Get-Content -LiteralPath $iniPath -Encoding UTF8
    $sections = @()
    $current = $null
    foreach ($line in $lines) {
        if ($line -match '^\[(.+)\]\s*$') {
            if ($current) { $sections += $current }
            $current = @{ Name = $Matches[1]; Props = @{} }
            continue
        }
        if ($current -and $line -match '^([^=]+)=(.*)$') {
            $current.Props[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    if ($current) { $sections += $current }

    $profileSections = @($sections | Where-Object { $_.Name -match '^Profile' })
    if ($profileSections.Count -eq 0) { return $null }

    $chosen = $profileSections | Where-Object { $_.Props['Default'] -eq '1' } | Select-Object -First 1
    if (-not $chosen) { $chosen = $profileSections[0] }

    $rel = $chosen.Props['Path']
    if ([string]::IsNullOrWhiteSpace($rel)) { return $null }

    $isRelative = ($chosen.Props['IsRelative'] -ne '0')
    if ($isRelative) {
        return (Join-Path $zenRoot ($rel -replace '/', '\'))
    }
    return $rel
}

function Invoke-BetterZen {
    param(
        [switch]$EnsureProfile,
        [switch]$NoPause
    )

    Write-Host "`n→ BetterZen (Betterfox zen/user.js)" -ForegroundColor Cyan
    $profilePath = Get-ZenDefaultProfilePath
    if (-not $profilePath -or -not (Test-Path -LiteralPath $profilePath)) {
        if ($EnsureProfile) {
            $profilePath = Initialize-ZenDefaultProfile
        }
        else {
            Write-Host "  Profil Zen introuvable sous %APPDATA%\zen." -ForegroundColor Red
            Write-Host "  Installe Zen et lance-le une fois pour créer un profil." -ForegroundColor DarkYellow
            if (-not $NoPause) { Wait-ForUser }
            return $false
        }
    }

    if (-not (Test-Path -LiteralPath $profilePath)) {
        New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
    }

    Write-Host "  Profil : $profilePath" -ForegroundColor DarkGray
    $url = 'https://raw.githubusercontent.com/yokoffing/Betterfox/main/zen/user.js'
    $dest = Join-Path $profilePath 'user.js'
    $tmp = Join-Path $env:TEMP 'fresh_windows-betterzen-user.js'

    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $tmp) -or ((Get-Item $tmp).Length -lt 100)) {
            throw 'Téléchargement BetterZen vide ou trop court.'
        }

        if (Test-Path -LiteralPath $dest) {
            $bak = Join-Path $profilePath ("user.js.bak-{0}" -f (Get-Date -Format 'yyyyMMdd'))
            Copy-Item -LiteralPath $dest -Destination $bak -Force
            Write-Host "  Backup : $bak" -ForegroundColor DarkGray
        }

        Copy-Item -LiteralPath $tmp -Destination $dest -Force
        Write-Host "  BetterZen écrit : $dest" -ForegroundColor Green
        Write-Host "  Ferme / relance Zen pour appliquer les prefs." -ForegroundColor Yellow
        if (-not $NoPause) { Wait-ForUser }
        return $true
    }
    catch {
        Write-Host "  Échec BetterZen : $($_.Exception.Message)" -ForegroundColor Red
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }
}

function Open-BraveProfileMenu {
    do {
        Clear-Host
        Write-Host "=== PROFIL BRAVE ===" -ForegroundColor Magenta
        Write-Host "Policies Fresh : Rewards/Wallet/VPN/Leo/News/Talk/télémétrie OFF." -ForegroundColor DarkGray
        Write-Host "Sync et Tor restent actifs. Vérif : brave://policy" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "1. Appliquer / réappliquer le profil" -ForegroundColor Green
        Write-Host "2. Retirer le profil (undo policies)" -ForegroundColor Yellow
        Write-Host "3. Retour" -ForegroundColor DarkGray
        Write-Host ""
        $c = Read-Host "Choix"
        switch ($c) {
            "1" { Invoke-BraveOptimize | Out-Null }
            "2" { Invoke-BraveOptimize -Remove | Out-Null }
            "3" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Open-Extensions {
    do {
        Clear-Host
        Write-Host "=== NAVIGATEURS / EXTENSIONS ===" -ForegroundColor Cyan
        Write-Host "Zen : Betterfox à l'install. Brave : profil Fresh à l'install." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "1. Extensions Firefox-based (Zen, Firefox...) - Recommandé" -ForegroundColor Green
        Write-Host "2. Extensions Chrome-based (Brave, Chrome, Edge...)" -ForegroundColor Yellow
        Write-Host "3. Profil Brave - réappliquer / retirer" -ForegroundColor Magenta
        Write-Host "4. Retour" -ForegroundColor DarkGray
        $c = Read-Host "Choix"

        switch ($c) {
            "1" {
                $urls = Get-Config -FileName "extensions-firefox-based.json"
                if (-not $urls) { Wait-ForUser; continue }
                Write-Host "`nOuverture des extensions Firefox-based..." -ForegroundColor Yellow
                foreach ($url in $urls) {
                    if ($url -notmatch '^https?://') {
                        Write-Host "  URL ignorée (schéma non http/https) : $url" -ForegroundColor DarkYellow
                        continue
                    }
                    Start-Process $url
                }
                Write-Host "Pages ouvertes (vrai uBlock Origin)." -ForegroundColor Green
                Wait-ForUser
            }
            "2" {
                $urls = Get-Config -FileName "extensions-chrome-based.json"
                if (-not $urls) { Wait-ForUser; continue }
                Write-Host "`nOuverture des extensions Chrome-based..." -ForegroundColor Yellow
                foreach ($url in $urls) {
                    if ($url -notmatch '^https?://') {
                        Write-Host "  URL ignorée (schéma non http/https) : $url" -ForegroundColor DarkYellow
                        continue
                    }
                    Start-Process $url
                }
                Write-Host "Pages ouvertes." -ForegroundColor Green
                Wait-ForUser
            }
            "3" { Open-BraveProfileMenu }
            "4" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Get-SystemProfileInfo {
    if ($script:SystemProfileInfo) { return $script:SystemProfileInfo }

    $user = [Environment]::UserName
    $profilePath = $env:USERPROFILE
    $edition = $null
    $displayVersion = $null

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $edition = $os.Caption
    } catch {
        $edition = 'Windows'
    }

    try {
        $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $displayVersion = if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }
    } catch {
        $displayVersion = '?'
    }

    $script:SystemProfileInfo = [pscustomobject]@{
        User           = $user
        Edition        = $edition
        DisplayVersion = $displayVersion
        ProfilePath    = $profilePath
    }
    return $script:SystemProfileInfo
}

function Show-Menu {
    Clear-Host
    $info = Get-SystemProfileInfo
    Write-Host "=============== FRESH WINDOWS ===============" -ForegroundColor Cyan
    Write-Host ("User    : {0}" -f $info.User) -ForegroundColor DarkGray
    Write-Host ("Windows : {0} ({1})" -f $info.Edition, $info.DisplayVersion) -ForegroundColor DarkGray
    Write-Host ("Profil  : {0}" -f $info.ProfilePath) -ForegroundColor DarkGray
    Write-Host ("Ref     : {0}" -f $RepoRef) -ForegroundColor DarkGray
    Write-Host "Apres formatage : 5 → 8 → 9 → 11" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "--- Installer ---" -ForegroundColor DarkCyan
    Write-Host " 1  Apps standard" -ForegroundColor Green
    Write-Host " 2  Apps gaming" -ForegroundColor Magenta
    Write-Host " 3  Apps dev" -ForegroundColor Blue
    Write-Host " 4  Apps custom (auto-detect)" -ForegroundColor DarkYellow
    Write-Host " 5  Full setup (1+2+3)" -ForegroundColor Cyan
    Write-Host "--- Configurer ---" -ForegroundColor DarkCyan
    Write-Host " 6  Navigateurs (extensions + profil Brave)" -ForegroundColor Yellow
    Write-Host " 7  Winget upgrade --all" -ForegroundColor White
    Write-Host " 8  Tweaks Windows (one-click, ShutUp10, presets)" -ForegroundColor Gray
    Write-Host " 9  Taches planifiees (MAJ + maintenance + sync scripts)" -ForegroundColor DarkCyan
    Write-Host "10  GPU / Chipset (AMD, NVIDIA, Intel DSA)" -ForegroundColor DarkYellow
    Write-Host "--- Mode jeu ---" -ForegroundColor DarkCyan
    Write-Host "11  Mode jeu (lancer / raccourci / agent)" -ForegroundColor Red
    Write-Host " 0  Quitter" -ForegroundColor DarkGray
    Write-Host ""
}

function Import-GameModeCommon {
    if (Get-Command Get-GameModeKillConfig -ErrorAction SilentlyContinue) {
        return $true
    }
    Write-Host "GameMode-Common.ps1 n'est pas charge (biblio). Relance le launcher." -ForegroundColor Red
    return $false
}

function Invoke-GameModeKill {
    param([switch]$NoPause)

    Write-Host "`n=== MODE JEU - fermeture processus lourds ===" -ForegroundColor Red
    Write-Host "Kill : dev / IA / sync / Bitwarden / ... Discord & Legcord proteges." -ForegroundColor DarkGray
    Write-Host "Launchers : familles (EA/Steam/...) - session active jamais tuee." -ForegroundColor DarkGray

    if (-not (Import-GameModeCommon)) {
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }

    Ensure-UltimatePerformanceActive | Out-Null

    $cfg = Get-GameModeKillConfig
    $result = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames
    $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames -LauncherFamilies $cfg.GamingLauncherFamilies

    if ($result.Killed.Count -gt 0) {
        Write-Host "`nFermes ($($result.Killed.Count)) :" -ForegroundColor Green
        $result.Killed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    }
    else {
        Write-Host "`nAucun process de la liste n'etait ouvert." -ForegroundColor Yellow
    }
    if ($result.Skipped.Count -gt 0) {
        Write-Host "Ignores / proteges :" -ForegroundColor DarkYellow
        $result.Skipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    }
    if ($idle.Notes) {
        foreach ($n in $idle.Notes) {
            Write-Host "  $n" -ForegroundColor DarkCyan
        }
    }
    if ($idle.Killed.Count -gt 0) {
        Write-Host "`nLaunchers idle fermes ($($idle.Killed.Count)) :" -ForegroundColor Green
        $idle.Killed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    }
    if ($idle.Kept.Count -gt 0) {
        Write-Host "Launchers conserves :" -ForegroundColor DarkCyan
        $idle.Kept | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    }

    Write-Host "`nAstuce : menu 11 → raccourci Bureau / agent barre des taches." -ForegroundColor DarkCyan
    if (-not $NoPause) { Wait-ForUser }
    return ($result.Skipped.Count -eq 0)
}

function Test-WatchAgentAlreadyInstalled {
    param([string]$FreshAppData)

    $cmdPath = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
    if (-not (Test-Path -LiteralPath $cmdPath)) { return $false }

    $task = Get-ScheduledTask -TaskName 'FreshWindows-WatchAgent' -ErrorAction SilentlyContinue
    if (-not $task) { return $false }

    foreach ($a in @($task.Actions)) {
        $exe = [string]$a.Execute
        if ($exe -and ($exe -eq $cmdPath -or $exe -like '*Start-WatchAgent.cmd*')) {
            return $true
        }
    }
    return $false
}

function Install-GameModeShortcuts {
    param([switch]$NoPause, [switch]$IncludeWatchAgent)

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null

    $iconPath = Join-Path $FreshAppData "fresh-windows.ico"
    if (-not (Test-Path -LiteralPath $iconPath)) {
        try { Invoke-WebRequest -Uri $IconUrl -OutFile $iconPath -UseBasicParsing } catch { }
    }

    try {
        Write-FreshWindowsLaunchStub -FreshAppData $FreshAppData -Ref $RepoRef -LauncherUrl $LauncherUrl | Out-Null
        Sync-GameModeLocalScripts -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $RepoRef -IconUrl $IconUrl | Out-Null
    }
    catch {
        Write-Host "Échec sync scripts locaux : $($_.Exception.Message)" -ForegroundColor Red
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }

    $killStub = Join-Path $FreshAppData "Launch-GameModeKill.ps1"
    $watchStub = Join-Path $FreshAppData "Launch-GameModeWatch.ps1"

    $wsh = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')

    $lnkKill = Join-Path $desktop "Mode Jeu.lnk"
    $k = $wsh.CreateShortcut($lnkKill)
    $k.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $k.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$killStub`""
    $k.WorkingDirectory = $FreshAppData
    $k.Description = "Fresh Windows - mode jeu (liste générique)"
    if (Test-Path -LiteralPath $iconPath) { $k.IconLocation = "$iconPath,0" }
    $k.Save()
    Write-Host "→ Raccourci Bureau : Mode Jeu.lnk (sans admin)" -ForegroundColor Green

    if ($IncludeWatchAgent) {
        # Retirer l'ancien Startup .lnk (cause du double agent avec la tache)
        $startup = [Environment]::GetFolderPath('Startup')
        $lnkWatch = Join-Path $startup "Fresh Windows Surveillance.lnk"
        if (Test-Path -LiteralPath $lnkWatch) {
            Remove-Item -LiteralPath $lnkWatch -Force -ErrorAction SilentlyContinue
            Write-Host "-> Ancien raccourci Startup retire (evite double icone)." -ForegroundColor DarkGray
        }

        if (Test-WatchAgentAlreadyInstalled -FreshAppData $FreshAppData) {
            Write-Host "-> Agent deja installe (tache FreshWindows-WatchAgent) - skip creation." -ForegroundColor Green
        }
        else {
            try {
                $taskName = Register-FreshWindowsWatchAgentLogon -FreshAppData $FreshAppData
                Write-Host "-> Tache planifiee : $taskName (AtLogOn Limited, delai 45s)" -ForegroundColor Green
            }
            catch {
                Write-Host "Tache planifiee non creee : $($_.Exception.Message)" -ForegroundColor DarkYellow
                # Fallback Startup uniquement si la tache echoue
                $w = $wsh.CreateShortcut($lnkWatch)
                $cmdWatch = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
                $w.TargetPath = $cmdWatch
                $w.Arguments = ''
                $w.WorkingDirectory = $FreshAppData
                $w.WindowStyle = 7
                $w.Description = "Agent Fresh Windows (fallback Startup)"
                if (Test-Path -LiteralPath $iconPath) { $w.IconLocation = "$iconPath,0" }
                $w.Save()
                Write-Host "-> Fallback Startup : Fresh Windows Surveillance.lnk" -ForegroundColor Yellow
            }
        }

        Write-Host "  Clic droit sur l'icone pour Detection auto." -ForegroundColor DarkGray
        try {
            Start-FreshWindowsUnelevated -FilePath $watchStub -WorkingDirectory $FreshAppData
            Write-Host "Agent lance maintenant (sans elevation). Fleche ^ si icone cachee." -ForegroundColor DarkCyan
        }
        catch {
            Write-Host "Raccourci OK, mais lancement immediat echoue : $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if (-not $NoPause) { Wait-ForUser }
    return $true
}

function Open-GameModeSetupMenu {
    do {
        Clear-Host
        Write-Host "=== MODE JEU ===" -ForegroundColor Red
        Write-Host "Scripts dans %LOCALAPPDATA%\FreshWindows (ref $RepoRef)." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "1. Lancer le mode jeu maintenant" -ForegroundColor Red
        Write-Host "2. Raccourci Bureau Mode Jeu" -ForegroundColor Green
        Write-Host "3. Agent au demarrage (+ lancer maintenant)" -ForegroundColor Cyan
        Write-Host "4. Retour" -ForegroundColor DarkGray
        Write-Host ""
        $sub = Read-Host "Choix"
        switch ($sub) {
            "1" { Invoke-GameModeKill | Out-Null }
            "2" { Install-GameModeShortcuts | Out-Null }
            "3" { Install-GameModeShortcuts -IncludeWatchAgent | Out-Null }
            "4" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Start-GameModeWatchAgent {
    param([switch]$NoPause)

    $ok = Install-GameModeShortcuts -NoPause -IncludeWatchAgent
    if (-not $ok) {
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }
    if (-not $NoPause) { Wait-ForUser }
    return $true
}

function Invoke-SilentMode {
    param([string]$InstallMode)

    $InstallMode = $InstallMode.Trim().ToLowerInvariant()
    if ($InstallMode -in @('winget-task', 'winutil-task')) {
        Write-Host "Alias '$InstallMode' → mode 'tasks'." -ForegroundColor DarkGray
        $InstallMode = 'tasks'
    }

    Write-Host "Mode silencieux : $InstallMode (ref=$RepoRef)" -ForegroundColor Cyan
    $ok = $true

    try {
        if ($InstallMode -like 'custom:*') {
            $packName = $InstallMode.Substring(7).Trim()
            if ([string]::IsNullOrWhiteSpace($packName)) {
                Write-Host "Mode custom: : nom de paquet manquant." -ForegroundColor Red
                exit 1
            }
            $ok = [bool](Install-CustomAppPackByName -Name $packName -NoPause)
        }
        else {
        switch ($InstallMode) {
            "standard" {
                $ok = [bool](Install-FromJson -FileName "apps-standard.json" -Category "Standard" -NoPause)
            }
            "gaming" {
                $ok = [bool](Install-FromJson -FileName "apps-gaming.json" -Category "Gaming" -NoPause)
            }
            "dev" {
                $ok = [bool](Install-FromJson -FileName "apps-dev.json" -Category "Dev" -NoPause)
            }
            "custom" {
                $ok = [bool](Install-AllCustomAppPacks -NoPause)
            }
            "full" {
                $ok = [bool](Install-FullSetup -NoPause)
            }
            "winutil-oneclick" {
                $ok = [bool](Invoke-WinUtilOneClick -NoPause)
            }
            "maintenance" {
                $ok = [bool](Invoke-MaintenanceReapply -NoPause)
            }
            "winutil-standard" {
                $ok = [bool](Invoke-WinUtilPreset -Preset Standard -NoPause)
            }
            "winutil-minimal" {
                $ok = [bool](Invoke-WinUtilPreset -Preset Minimal -NoPause)
            }
            "winutil-advanced" {
                $ok = [bool](Invoke-WinUtilPreset -Preset Advanced -NoPause)
            }
            "winutil-appx" {
                $ok = [bool](Invoke-WinUtilConfig -ConfigUrl "$BaseUrl/winutil-appx.json" -Label "AppX bloat" -NoPause)
            }
            "brave-debloat" {
                $ok = [bool](Invoke-BraveOptimize -NoPause)
            }
            "brave-optimize" {
                $ok = [bool](Invoke-BraveOptimize -NoPause)
            }
            "betterzen" {
                $ok = [bool](Invoke-BetterZen -EnsureProfile -NoPause)
            }
            "tasks" {
                $ok = [bool](Register-AllScheduledTasks -NoPause)
            }
            "game-mode" {
                $ok = [bool](Invoke-GameModeKill -NoPause)
            }
            "game-mode-shortcuts" {
                $ok = [bool](Install-GameModeShortcuts -NoPause)
            }
            "game-mode-watch" {
                $ok = [bool](Start-GameModeWatchAgent -NoPause)
            }
            "powertoys-profile" {
                $ok = [bool](Apply-PowerToysProfile)
            }
            "shutup10" {
                $ok = [bool](Invoke-ShutUp10Recommended -NoPause)
            }
            "winget-upgrade" {
                $ok = [bool](Invoke-WingetUpgradeAll -NoPause)
            }
            default {
                Write-Host "Mode inconnu : $InstallMode" -ForegroundColor Red
                exit 1
            }
        }
        }
    }
    catch {
        Write-Host "Erreur fatale (mode $InstallMode) : $($_.Exception.Message)" -ForegroundColor Red
        $ok = $false
    }

    if (-not $ok) {
        Write-Host "`nÉchec - exit 1 (voir messages ci-dessus)." -ForegroundColor Red
        exit 1
    }
    Write-Host "`nOK - exit 0" -ForegroundColor Green
    exit 0
}

function Install-FreshWindowsDesktopShortcut {
    $marker = Join-Path $FreshAppData "desktop-shortcut.done"
    if (Test-Path -LiteralPath $marker) { return }

    try {
        New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null

        $iconPath = Join-Path $FreshAppData "fresh-windows.ico"
        if (-not (Test-Path -LiteralPath $iconPath)) {
            Write-Host "→ Icône Fresh Windows..." -ForegroundColor DarkCyan
            Invoke-WebRequest -Uri $IconUrl -OutFile $iconPath -UseBasicParsing
        }

        $stubPath = Write-FreshWindowsLaunchStub -FreshAppData $FreshAppData -Ref $RepoRef -LauncherUrl $LauncherUrl

        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnkPath = Join-Path $desktop "Fresh Windows.lnk"

        $wsh = New-Object -ComObject WScript.Shell
        $lnk = $wsh.CreateShortcut($lnkPath)
        $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$stubPath`""
        $lnk.WorkingDirectory = $FreshAppData
        $lnk.WindowStyle = 1
        $lnk.Description = "Fresh Windows (GitHub) - admin"
        if (Test-Path -LiteralPath $iconPath) {
            $lnk.IconLocation = "$iconPath,0"
        }
        $lnk.Save()

        # Demander élévation via le raccourci (bit RunAs)
        try {
            $bytes = [IO.File]::ReadAllBytes($lnkPath)
            # Shortcut flags at offset 0x15: set RunAsAdmin bit (0x20)
            if ($bytes.Length -gt 0x15) {
                $bytes[0x15] = $bytes[0x15] -bor 0x20
                [IO.File]::WriteAllBytes($lnkPath, $bytes)
            }
        } catch { }

        Set-Content -LiteralPath $marker -Value (Get-Date -Format o) -Encoding UTF8
        Write-Host "→ Raccourci Bureau créé : Fresh Windows.lnk" -ForegroundColor Green
    }
    catch {
        Write-Host "Raccourci Bureau non créé : $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# ========== ENTRÉE ==========
if ($Mode -ne 'menu') {
    Invoke-SilentMode -InstallMode $Mode
    exit
}

Install-FreshWindowsDesktopShortcut

do {
    Show-Menu
    $choice = Read-Host "Ton choix"

    try {
        switch ($choice) {
            "1" { Install-FromJson -FileName "apps-standard.json" -Category "Standard" | Out-Null }
            "2" { Install-FromJson -FileName "apps-gaming.json" -Category "Gaming" | Out-Null }
            "3" { Install-FromJson -FileName "apps-dev.json" -Category "Dev" | Out-Null }
            "4" { Open-CustomAppsMenu }
            "5" { Install-FullSetup | Out-Null }
            "6" { Open-Extensions }
            "7" { Invoke-WingetUpgradeAll | Out-Null }
            "8" { Open-WinUtilMenu }
            "9" { Open-ScheduledTasksMenu }
            "10" { Open-GpuMenu }
            "11" { Open-GameModeSetupMenu }
            "0" { exit 0 }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    }
    catch {
        Write-Host "`nErreur : $($_.Exception.Message)" -ForegroundColor Red
        Wait-ForUser
    }
} while ($true)
