#Requires -RunAsAdministrator
# ============================================================
#  Fresh Windows - toolbox reinstall / maintenance
#  Configs lues depuis GitHub (édition à distance)
#
#  Modes non interactifs :
#    $env:FRESH_WIN_MODE='full'; irm ... | iex
#    Apps : standard | gaming | dev | full
#    WinUtil : winutil-oneclick | winutil-standard | winutil-minimal |
#              winutil-advanced | winutil-appx | maintenance
#    Autre : tasks | game-mode | game-mode-shortcuts | game-mode-watch |
#            powertoys-profile | shutup10 | brave-debloat | betterzen
#
#  Pin de version (commit / tag / branche) :
#    $env:FRESH_WIN_REF='abc1234'
#    irm https://raw.githubusercontent.com/nico2511/fresh_windows/$env:FRESH_WIN_REF/launcher.ps1 | iex
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

# Source unique : listes JSON sur GitHub (pas de configs locales)
$RepoRawRoot = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef"
$RepoBlobRoot = "https://github.com/nico2511/fresh_windows/blob/$RepoRef"
$BaseUrl = "$RepoRawRoot/configs"
$GuidesBaseUrl = "$RepoBlobRoot/guides"
$LauncherUrl = "$RepoRawRoot/launcher.ps1"
$IconUrl = "$RepoRawRoot/assets/fresh-windows.ico"
$FreshAppData = Join-Path $env:LOCALAPPDATA "FreshWindows"
$script:FreshBrand = "Fresh Windows"
# Incrémenter quand les libs changent alors que FRESH_WIN_REF reste "main" (sinon cache périmé)
$script:FreshWindowsLibEpoch = 16

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
    param([string]$FileName)
    try {
        $url  = "$BaseUrl/$FileName"
        $json = Invoke-RestMethod -Uri $url -UseBasicParsing
        if ($null -eq $json) {
            throw "Config vide ou invalide."
        }
        return @($json)
    }
    catch {
        Write-Host "Erreur lors du téléchargement de $FileName" -ForegroundColor Red
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

    if ($App.shortcut -eq $true) {
        try {
            $programs = [Environment]::GetFolderPath('Programs')
            $lnkPath  = Join-Path $programs "$name.lnk"
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut($lnkPath)
            $lnk.TargetPath = $destPath
            $lnk.WorkingDirectory = $destDir
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
        [string]$Category,
        [switch]$NoPause
    )
    $apps = Get-Config -FileName $FileName
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
    param([switch]$NoPause)

    Write-Host "`n→ BetterZen (Betterfox zen/user.js)" -ForegroundColor Cyan
    $profilePath = Get-ZenDefaultProfilePath
    if (-not $profilePath -or -not (Test-Path -LiteralPath $profilePath)) {
        Write-Host "  Profil Zen introuvable sous %APPDATA%\zen." -ForegroundColor Red
        Write-Host "  Installe Zen et lance-le une fois pour créer un profil." -ForegroundColor DarkYellow
        if (-not $NoPause) { Wait-ForUser }
        return $false
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

function Open-Extensions {
    do {
        Clear-Host
        Write-Host "=== NAVIGATEURS / EXTENSIONS ===" -ForegroundColor Cyan
        Write-Host "1. Extensions Firefox-based (Zen, Firefox...) - Recommandé" -ForegroundColor Green
        Write-Host "2. Extensions Chrome-based (Brave, Chrome, Edge...)" -ForegroundColor Yellow
        Write-Host "3. Brave - debloat (WinUtil)" -ForegroundColor Magenta
        Write-Host "4. Zen - BetterZen (user.js)" -ForegroundColor Cyan
        Write-Host "5. Retour" -ForegroundColor DarkGray
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
            "3" {
                Invoke-WinUtilConfig -ConfigUrl "$BaseUrl/winutil-brave-debloat.json" -Label "Brave debloat"
            }
            "4" {
                Invoke-BetterZen | Out-Null
            }
            "5" { return }
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
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "              FRESH WINDOWS (GitHub)" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ("User    : {0}" -f $info.User) -ForegroundColor DarkGray
    Write-Host ("Windows : {0} ({1})" -f $info.Edition, $info.DisplayVersion) -ForegroundColor DarkGray
    Write-Host ("Profil  : {0}" -f $info.ProfilePath) -ForegroundColor DarkGray
    Write-Host "Ref GitHub : $RepoRef" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "--- Install ---" -ForegroundColor DarkCyan
    Write-Host "1. Apps Standard" -ForegroundColor Green
    Write-Host "2. Apps Gaming" -ForegroundColor Magenta
    Write-Host "3. Apps Dev" -ForegroundColor Blue
    Write-Host "4. Full (1+2+3)" -ForegroundColor Cyan
    Write-Host "--- Maintien ---" -ForegroundColor DarkCyan
    Write-Host "5. Navigateurs / extensions" -ForegroundColor Yellow
    Write-Host "6. Winget upgrade --all" -ForegroundColor White
    Write-Host "7. WinUtil / ShutUp10" -ForegroundColor Gray
    Write-Host "8. Tâches planifiées (+ maintenance dimanche)" -ForegroundColor DarkCyan
    Write-Host "9. GPU AMD / NVIDIA" -ForegroundColor DarkYellow
    Write-Host "--- Session jeu ---" -ForegroundColor DarkCyan
    Write-Host "10. Mode jeu - exécuter maintenant" -ForegroundColor Red
    Write-Host "11. Mode jeu - raccourci & agent (sous-menu)" -ForegroundColor DarkRed
    Write-Host "0. Quitter" -ForegroundColor DarkGray
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
    Write-Host "Liste générique (dev / IA / 3D / vidéo / sync). Comm protégée ; launchers inactifs fermés." -ForegroundColor DarkGray

    if (-not (Import-GameModeCommon)) {
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }

    $cfg = Get-GameModeKillConfig
    $result = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames
    $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames

    if ($result.Killed.Count -gt 0) {
        Write-Host "`nFermés ($($result.Killed.Count)) :" -ForegroundColor Green
        $result.Killed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    }
    else {
        Write-Host "`nAucun process de la liste n'était ouvert." -ForegroundColor Yellow
    }
    if ($result.Skipped.Count -gt 0) {
        Write-Host "Ignorés / protégés :" -ForegroundColor DarkYellow
        $result.Skipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    }
    if ($idle.Killed.Count -gt 0) {
        Write-Host "`nLaunchers gaming inactifs fermés ($($idle.Killed.Count)) :" -ForegroundColor Green
        $idle.Killed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
        if ($idle.Kept.Count -gt 0) {
            Write-Host "Launcher conservé : $($idle.Kept -join ', ')" -ForegroundColor DarkCyan
        }
    }

    Write-Host "`nAstuce : raccourci Bureau Mode Jeu ou agent barre des taches (menu 11)." -ForegroundColor DarkCyan
    Write-Host "Plan Ultimate Performance : menu WinUtil one-click." -ForegroundColor DarkCyan
    if (-not $NoPause) { Wait-ForUser }
    return ($result.Skipped.Count -eq 0)
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
        $startup = [Environment]::GetFolderPath('Startup')
        $lnkWatch = Join-Path $startup "Fresh Windows Surveillance.lnk"
        $w = $wsh.CreateShortcut($lnkWatch)
        $cmdWatch = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
        $w.TargetPath = $cmdWatch
        $w.Arguments = ''
        $w.WorkingDirectory = $FreshAppData
        $w.WindowStyle = 7
        $w.Description = "Agent Fresh Windows (CPU/RAM/disque/hang + toggle auto)"
        if (Test-Path -LiteralPath $iconPath) { $w.IconLocation = "$iconPath,0" }
        $w.Save()
        Write-Host "-> Demarrage Windows : Fresh Windows Surveillance.lnk" -ForegroundColor Green

        try {
            $taskName = Register-FreshWindowsWatchAgentLogon -FreshAppData $FreshAppData
            Write-Host "-> Tache planifiee : $taskName (AtLogOn Limited, delai 45s)" -ForegroundColor Green
        }
        catch {
            Write-Host "Tache planifiee non creee : $($_.Exception.Message)" -ForegroundColor DarkYellow
            Write-Host "  Le raccourci Startup reste en place." -ForegroundColor DarkGray
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
        Write-Host "=== MODE JEU - raccourci & agent ===" -ForegroundColor Red
        Write-Host "Scripts copiés dans %LOCALAPPDATA%\FreshWindows (ref $RepoRef)." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "1. Raccourci Bureau Mode Jeu (sans admin)" -ForegroundColor Green
        Write-Host "2. Raccourci + agent au démarrage Windows" -ForegroundColor Cyan
        Write-Host "3. Lancer l'agent maintenant" -ForegroundColor Yellow
        Write-Host "4. Retour" -ForegroundColor DarkGray
        Write-Host ""
        $sub = Read-Host "Choix"
        switch ($sub) {
            "1" { Install-GameModeShortcuts | Out-Null }
            "2" { Install-GameModeShortcuts -IncludeWatchAgent | Out-Null }
            "3" { Start-GameModeWatchAgent | Out-Null }
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

    # Reinstalle aussi Startup + tache logon (repare un agent qui ne repart plus au boot)
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
                $ok = [bool](Invoke-WinUtilConfig -ConfigUrl "$BaseUrl/winutil-brave-debloat.json" -Label "Brave debloat" -NoPause)
            }
            "betterzen" {
                $ok = [bool](Invoke-BetterZen -NoPause)
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
            "4" { Install-FullSetup | Out-Null }
            "5" { Open-Extensions }
            "6" { Invoke-WingetUpgradeAll | Out-Null }
            "7" { Open-WinUtilMenu }
            "8" { Open-ScheduledTasksMenu }
            "9" { Open-GpuMenu }
            "10" { Invoke-GameModeKill }
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
