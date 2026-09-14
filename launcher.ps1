#Requires -RunAsAdministrator
# ============================================================
#  Fresh Windows — toolbox reinstall / maintenance
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

# Via env (compatible irm | iex) — pas de param() qui casse le pipe
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

function Get-FreshWindowsBootstrapScriptPath {
    param(
        [Parameter(Mandatory)][string]$CacheFileName,
        [Parameter(Mandatory)][string]$RemotePath
    )

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $dest = Join-Path $FreshAppData $CacheFileName
    $meta = Join-Path $FreshAppData "$CacheFileName.ref"
    $url  = "$RepoRawRoot/$RemotePath"
    $needFetch = -not (Test-Path -LiteralPath $dest)
    if (-not $needFetch -and (Test-Path -LiteralPath $meta)) {
        try {
            if ((Get-Content -LiteralPath $meta -Raw -Encoding UTF8).Trim() -ne $RepoRef) {
                $needFetch = $true
            }
        }
        catch { $needFetch = $true }
    }
    elseif (-not (Test-Path -LiteralPath $meta)) { $needFetch = $true }

    if ($needFetch) {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Set-Content -LiteralPath $meta -Value $RepoRef -Encoding UTF8 -NoNewline
    }
    return $dest
}

function Import-FreshWindowsLibraries {
    $libRoot = Join-Path $PSScriptRoot 'scripts/lib'
    $localImport = Join-Path $libRoot 'Import-CachedScript.ps1'
    $localCore   = Join-Path $libRoot 'Launcher-Core.ps1'

    if ($PSScriptRoot -and (Test-Path -LiteralPath $localImport) -and (Test-Path -LiteralPath $localCore)) {
        . $localImport
        . $localCore
        return $true
    }

    try {
        $importPath = Get-FreshWindowsBootstrapScriptPath `
            -CacheFileName 'Import-CachedScript.ps1' `
            -RemotePath 'scripts/lib/Import-CachedScript.ps1'
        . $importPath

        $corePath = Get-FreshWindowsCachedScriptPath `
            -CacheFileName 'Launcher-Core.ps1' `
            -RemotePath 'scripts/lib/Launcher-Core.ps1' `
            -RepoRawRoot $RepoRawRoot `
            -RepoRef $RepoRef `
            -FreshAppData $FreshAppData
        . $corePath
        return $true
    }
    catch {
        Write-Host "Bibliothèques Fresh Windows indisponibles : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

if (-not (Import-FreshWindowsLibraries)) {
    Write-Host "Impossible de charger scripts/lib (réseau ou repo). Arrêt." -ForegroundColor Red
    exit 1
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

    Write-Progress -Activity "Installation : $Category" -Status "$Current / $Total — $App" -PercentComplete $pct
    Write-Host ("  [{0}] {1,3}%  ({2}/{3})  {4}" -f $bar, $pct, $Current, $Total, $App) -ForegroundColor DarkCyan
    try { $Host.UI.RawUI.WindowTitle = "Fresh Windows [$Current/$Total] $Category — $App" } catch { }
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
            Write-Host "    déjà présent (winget) — skip" -ForegroundColor Green
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

function Find-ShutUp10Executable {
    $candidates = @()

    # WinUtil cache
    $candidates += Join-Path $env:LOCALAPPDATA "winutil\ooshutup10.exe"

    # Winget links / packages (portable)
    $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ooshutup10.exe"
    $candidates += $link

    try {
        $pkgRoots = @(
            (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"),
            (Join-Path $env:ProgramFiles "WinGet\Packages")
        )
        foreach ($root in $pkgRoots) {
            if (Test-Path $root) {
                Get-ChildItem $root -Directory -Filter "OO-Software.ShutUp10*" -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        Get-ChildItem $_.FullName -Recurse -Filter "ooshutup10*.exe" -ErrorAction SilentlyContinue |
                            Select-Object -First 2 -ExpandProperty FullName
                    } | ForEach-Object { $candidates += $_ }
            }
        }
    } catch { }

    # PATH
    $cmd = Get-Command ooshutup10.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-ShutUp10Exe {
    $exe = Find-ShutUp10Executable
    if ($exe) { return $exe }

    # Fallback : portable officiel (comme WinUtil)
    $destDir = Join-Path $env:LOCALAPPDATA "winutil"
    $dest = Join-Path $destDir "ooshutup10.exe"
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Write-Host "  → Téléchargement O&O ShutUp10 (portable)..." -ForegroundColor Gray
    try {
        # URL winget / package O&O (version flottante via page produit si besoin)
        $url = "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        if (Test-Path -LiteralPath $dest) { return $dest }
    }
    catch {
        Write-Host "    Échec download ShutUp10 : $($_.Exception.Message)" -ForegroundColor Red
    }
    return $null
}

function Invoke-ShutUp10Recommended {
    param(
        [switch]$LaunchGui,
        [switch]$NoPause
    )

    Write-Host "`n→ O&O ShutUp10++" -ForegroundColor Cyan
    $exe = Get-ShutUp10Exe
    if (-not $exe) {
        Write-Host "  ShutUp10 introuvable. Installe OO-Software.ShutUp10 (apps standard) d'abord." -ForegroundColor Red
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }

    Write-Host "  Exe : $exe" -ForegroundColor DarkGray

    $cfgUrl = "$BaseUrl/shutup10-recommended.cfg"
    $cfgLocal = Join-Path $env:TEMP "fresh_windows-shutup10-recommended.cfg"
    $cfgOk = $false
    $cfgDownloaded = $false

    try {
        Invoke-WebRequest -Uri $cfgUrl -OutFile $cfgLocal -UseBasicParsing -ErrorAction Stop
        if ((Test-Path $cfgLocal) -and ((Get-Item $cfgLocal).Length -gt 50)) {
            $cfgDownloaded = $true
            # Format applyable : SettingID[TAB]+|-   (pas le OOSU10.cfg UI)
            # CLI officiel : ooshutup10.exe <ConfigFile> [/quiet] [/nosrp] [/lang:xx]
            Write-Host "  → Import silencieux du profil GitHub..." -ForegroundColor Yellow
            $p = Start-Process -FilePath $exe -ArgumentList @(
                $cfgLocal, '/quiet', '/nosrp', '/lang:fr'
            ) -PassThru -Wait -WindowStyle Hidden
            if ($p.ExitCode -eq 0) {
                Write-Host "  Profil recommandé appliqué (quiet)." -ForegroundColor Green
                $cfgOk = $true
            }
            else {
                Write-Host "  Échec import quiet (code $($p.ExitCode))." -ForegroundColor DarkYellow
            }
        }
    }
    catch {
        Write-Host "  Impossible de télécharger shutup10-recommended.cfg : $($_.Exception.Message)" -ForegroundColor DarkGray
    }

    if ($LaunchGui) {
        Write-Host "  Ouverture GUI ShutUp10..." -ForegroundColor DarkGray
        Start-Process -FilePath $exe
    }
    elseif (-not $cfgOk) {
        if ($NoPause) {
            if ($cfgDownloaded) {
                Write-Host "  Mode silencieux : import échoué — ShutUp10 non appliqué (pas de GUI)." -ForegroundColor DarkYellow
            }
            else {
                Write-Host "  Mode silencieux : cfg GitHub absent — ShutUp10 ignoré." -ForegroundColor DarkYellow
            }
        }
        else {
            Write-Host "  Ouverture GUI (applique manuellement Actions → paramètres recommandés)." -ForegroundColor Yellow
            Start-Process -FilePath $exe
        }
    }

    if (-not $NoPause) { Wait-ForUser }
    return ($cfgOk -or $LaunchGui)
}

function Get-FreshWindowsLogDir {
    $dir = Join-Path $FreshAppData 'logs'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Write-FreshStep {
    param(
        [string]$Title,
        [string]$Detail = '',
        [ConsoleColor]$Color = 'Cyan'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host ""
    Write-Host ("[{0}] {1}" -f $ts, $Title) -ForegroundColor $Color
    if ($Detail) {
        Write-Host ("         {0}" -f $Detail) -ForegroundColor DarkGray
    }
    try { $Host.UI.RawUI.WindowTitle = "Fresh Windows — $Title" } catch { }
}

function Invoke-MaintenanceReapply {
    param([switch]$NoPause)

    $logPath = $null
    try {
        $logPath = Join-Path (Get-FreshWindowsLogDir) ("maintenance-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Start-Transcript -Path $logPath -Force | Out-Null
    } catch { }

    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "       FRESH WINDOWS — MAINTENANCE HEBDO" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "Étapes : 1) WinUtil one-click  2) ShutUp10 quiet" -ForegroundColor DarkGray
    if ($logPath) {
        Write-Host "Log    : $logPath" -ForegroundColor DarkGray
    }
    Write-Host "Ref    : $RepoRef" -ForegroundColor DarkGray

    Write-FreshStep -Title "[1/2] WinUtil one-click" -Detail "Standard + AppX + prefs + Ultimate Performance (peut prendre plusieurs minutes)" -Color Yellow
    $wuOk = Invoke-WinUtilOneClick -NoPause
    if ($wuOk) {
        Write-FreshStep -Title "[1/2] WinUtil — OK" -Color Green
    }
    else {
        Write-FreshStep -Title "[1/2] WinUtil — ÉCHEC" -Color Red
    }

    Write-FreshStep -Title "[2/2] ShutUp10 quiet" -Detail "Import du cfg GitHub (sans GUI)" -Color Yellow
    $suOk = Invoke-ShutUp10Recommended -NoPause
    if ($suOk) {
        Write-FreshStep -Title "[2/2] ShutUp10 — OK" -Color Green
    }
    else {
        Write-FreshStep -Title "[2/2] ShutUp10 — ÉCHEC" -Color Red
    }

    $ok = [bool]$wuOk -and [bool]$suOk
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    if ($ok) {
        Write-Host "  MAINTENANCE TERMINÉE — OK" -ForegroundColor Green
    }
    else {
        Write-Host "  MAINTENANCE TERMINÉE — AVEC ERREURS" -ForegroundColor Red
        Write-Host ("  WinUtil={0}  ShutUp10={1}" -f $wuOk, $suOk) -ForegroundColor DarkYellow
    }
    if ($logPath) {
        Write-Host "  Log : $logPath" -ForegroundColor DarkGray
    }
    Write-Host "=======================================================" -ForegroundColor Cyan

    try { Stop-Transcript | Out-Null } catch { }

    if ($NoPause) {
        Write-Host "`nFermeture dans 20 secondes..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 20
    }
    else {
        Wait-ForUser
    }
    return $ok
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
        Write-Host "  ($($failed.Count)/$total en échec — codes winget / réseau non ignorés)" -ForegroundColor DarkYellow
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
        Write-Host "3. Brave — debloat (WinUtil)" -ForegroundColor Magenta
        Write-Host "4. Zen — BetterZen (user.js)" -ForegroundColor Cyan
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

function Set-RegistryDWord {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type DWord -Force
}

function Invoke-WinUtilPreferences {
    # Customize Preferences utiles (WinUtil ne les applique pas via -Config AutoRun)
    Write-Host "  → Dark Mode" -ForegroundColor Gray
    Set-RegistryDWord "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" 0
    Set-RegistryDWord "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "SystemUsesLightTheme" 0

    Write-Host "  → Game Mode" -ForegroundColor Gray
    Set-RegistryDWord "HKCU:\Software\Microsoft\GameBar" "AllowAutoGameMode" 1
    Set-RegistryDWord "HKCU:\Software\Microsoft\GameBar" "AutoGameModeEnabled" 1

    Write-Host "  → Extensions de fichiers visibles" -ForegroundColor Gray
    Set-RegistryDWord "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0

    Write-Host "  → Fichiers cachés visibles" -ForegroundColor Gray
    Set-RegistryDWord "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1

    Write-Host "  → Long Paths" -ForegroundColor Gray
    Set-RegistryDWord "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" 1

    Write-Host "  → Désactiver Bing Search (menu Démarrer)" -ForegroundColor Gray
    Set-RegistryDWord "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
    Set-RegistryDWord "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0

    # Rafraîchir Explorer pour le thème / fichiers
    try {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        Start-Process explorer
    } catch { }
}

function Enable-UltimatePerformance {
    Write-Host "  → Ultimate Performance (power plan)" -ForegroundColor Gray
    $schemeGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    $dup = powercfg /duplicatescheme $schemeGuid 2>&1 | Out-String
    $match = [regex]::Match($dup, '[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}')
    if ($match.Success) {
        powercfg /setactive $match.Value | Out-Null
        Write-Host "    Plan activé : $($match.Value)" -ForegroundColor DarkGray
    }
    else {
        # Déjà présent : activer s'il existe dans la liste
        $list = powercfg /list 2>&1 | Out-String
        $existing = [regex]::Match($list, '(?i)([A-Fa-f0-9-]{36}).*Ultimate Performance')
        if ($existing.Success) {
            powercfg /setactive $existing.Groups[1].Value | Out-Null
            Write-Host "    Plan Ultimate déjà présent, activé." -ForegroundColor DarkGray
        }
        else {
            Write-Host "    Impossible d'activer Ultimate Performance." -ForegroundColor Red
            Write-Host "    $dup" -ForegroundColor DarkRed
        }
    }
}

function Invoke-WinUtilOneClick {
    param([switch]$NoPause)

    $configUrl = "$BaseUrl/winutil-oneclick.json"
    Write-Host "`n=== PROFIL ONE-CLICK (WinUtil) ===" -ForegroundColor Cyan
    Write-Host "Tweaks Standard + AppX bloat + Hyper-V + prefs + Ultimate Performance" -ForegroundColor DarkGray
    Write-Host "Config : $configUrl" -ForegroundColor DarkGray

    $ok = $false
    try {
        Write-Host "`n[1/3] WinUtil : Standard + AppX (safe) + Hyper-V..." -ForegroundColor Yellow
        & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Config $configUrl

        Write-Host "`n[2/3] Customize Preferences..." -ForegroundColor Yellow
        Invoke-WinUtilPreferences

        Write-Host "`n[3/3] Mode Performance..." -ForegroundColor Yellow
        Enable-UltimatePerformance

        Write-Host "`nProfil one-click terminé. Un redémarrage peut être requis (Hyper-V)." -ForegroundColor Green
        $ok = $true
    }
    catch {
        Write-Host "Échec du profil one-click" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        $ok = $false
    }

    if (-not $NoPause) { Wait-ForUser }
    return $ok
}

function Invoke-WinUtilConfig {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigUrl,
        [string]$Label = "config",
        [switch]$NoPause
    )

    Write-Host "`n→ WinUtil $Label (sans UI, via -Config)..." -ForegroundColor Yellow
    Write-Host "  Config : $ConfigUrl" -ForegroundColor DarkGray
    $ok = $false
    try {
        & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Config $ConfigUrl
        Write-Host "`n$Label terminé." -ForegroundColor Green
        $ok = $true
    }
    catch {
        Write-Host "Échec WinUtil $Label" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        $ok = $false
    }
    if (-not $NoPause) { Wait-ForUser }
    return $ok
}

function Invoke-WinUtilPreset {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Standard', 'Minimal', 'Advanced')]
        [string]$Preset,
        [switch]$NoPause
    )

    Write-Host "`n→ WinUtil preset '$Preset' (sans UI)..." -ForegroundColor Yellow
    Write-Host "  Source : https://christitus.com/win" -ForegroundColor DarkGray
    $ok = $false
    try {
        & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Preset $Preset
        Write-Host "`nPreset '$Preset' terminé." -ForegroundColor Green
        $ok = $true
    }
    catch {
        Write-Host "Échec WinUtil preset '$Preset'" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
        $ok = $false
    }
    if (-not $NoPause) { Wait-ForUser }
    return $ok
}

function Open-WinUtilMenu {
    do {
        Clear-Host
        Write-Host "=== WINUTIL ===" -ForegroundColor Cyan
        Write-Host "Calibrage Windows via WinUtil (Chris Titus)." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "1. PROFIL ONE-CLICK  ★" -ForegroundColor Green
        Write-Host "   Standard + AppX bloat + Dark/Game Mode + Hyper-V + Ultimate Perf" -ForegroundColor DarkGreen
        Write-Host ""
        Write-Host "2. Preset Standard (WinUtil)" -ForegroundColor Yellow
        Write-Host "3. Preset Minimal (WinUtil)" -ForegroundColor Yellow
        Write-Host "4. Preset Advanced (WinUtil)" -ForegroundColor Magenta
        Write-Host "5. AppX bloat — retire les apps safe (via -Config)" -ForegroundColor DarkYellow
        Write-Host "6. O&O ShutUp10 — profil recommandé (GUI / cfg)" -ForegroundColor White
        Write-Host "7. Ouvrir WinUtil (interface graphique)" -ForegroundColor Gray
        Write-Host "8. Retour" -ForegroundColor DarkGray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" { Invoke-WinUtilOneClick }
            "2" { Invoke-WinUtilPreset -Preset Standard }
            "3" { Invoke-WinUtilPreset -Preset Minimal }
            "4" { Invoke-WinUtilPreset -Preset Advanced }
            "5" { Invoke-WinUtilConfig -ConfigUrl "$BaseUrl/winutil-appx.json" -Label "AppX bloat" }
            "6" { Invoke-ShutUp10Recommended -LaunchGui }
            "7" {
                Write-Host "Lancement de WinUtil (GUI)..." -ForegroundColor Yellow
                irm "https://christitus.com/win" | iex
            }
            "8" { return }
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
    Write-Host "10. Mode jeu — exécuter maintenant" -ForegroundColor Red
    Write-Host "11. Mode jeu — raccourci & agent (sous-menu)" -ForegroundColor DarkRed
    Write-Host "0. Quitter" -ForegroundColor DarkGray
    Write-Host ""
}

$script:WingetUpgradeTaskName = "FreshWindows-WingetUpgrade"
$script:WinUtilReapplyTaskName = "FreshWindows-WinUtilReapply"

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = [Security.Principal.WindowsPrincipal]::new($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
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

    # 1) Winget quotidien 12:00 + rattrapage
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

        Write-Host "  [OK] $script:WingetUpgradeTaskName — tous les jours 12:00 (+ rattrapage)" -ForegroundColor Green
    }
    catch {
        Write-Host "  [KO] Winget : $($_.Exception.Message)" -ForegroundColor Red
        $ok = $false
    }

    # 2) WinUtil + ShutUp10 dimanche 12:00 + rattrapage
    # Fenêtre visible : étapes + log (pas Hidden — sinon on ne voit rien)
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

        Write-Host "  [OK] $script:WinUtilReapplyTaskName — dimanche 12:00 (+ rattrapage)" -ForegroundColor Green
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
            Write-Host "⚠️  Pas en admin — l'activation échouera (Accès refusé)." -ForegroundColor Red
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

function Open-GpuMenu {
    $gpu = Get-ConfigObject -FileName "gpu.json"
    do {
        Clear-Host
        Write-Host "=== CARTE GRAPHIQUE ===" -ForegroundColor Cyan
        Write-Host "1. AMD" -ForegroundColor Red
        Write-Host "2. NVIDIA" -ForegroundColor Green
        Write-Host "3. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" { Open-AmdGpuMenu -GpuConfig $gpu }
            "2" { Open-NvidiaGpuMenu -GpuConfig $gpu }
            "3" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Open-AmdGpuMenu {
    param($GpuConfig)
    do {
        Clear-Host
        Write-Host "=== AMD / ADRENALIN ===" -ForegroundColor Red
        Write-Host "1. Télécharger Adrenalin (setup minimal)" -ForegroundColor Yellow
        Write-Host "2. Ouvrir la page drivers AMD" -ForegroundColor White
        Write-Host "3. Ouvrir le guide de config Adrenalin" -ForegroundColor Cyan
        Write-Host "4. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" {
                $url = if ($GpuConfig -and $GpuConfig.amd.downloadUrl) { $GpuConfig.amd.downloadUrl } else {
                    "https://drivers.amd.com/drivers/installer/26.10/whql/amd-software-adrenalin-edition-26.8.1-minimalsetup-260818_web.exe"
                }
                $dest = Join-Path $env:TEMP "amd-adrenalin-minimalsetup.exe"
                Write-Host "`n→ Téléchargement Adrenalin..." -ForegroundColor Yellow
                Write-Host "  $url" -ForegroundColor DarkGray
                try {
                    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
                    Write-Host "  Sauvé : $dest" -ForegroundColor Green
                    Start-Process $dest
                }
                catch {
                    Write-Host "Échec téléchargement : $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "Ouverture de la page drivers à la place..." -ForegroundColor Yellow
                    $page = if ($GpuConfig) { $GpuConfig.amd.driversPage } else { "https://www.amd.com/en/support/download/drivers.html" }
                    Start-Process $page
                }
                Wait-ForUser
            }
            "2" {
                $page = if ($GpuConfig) { $GpuConfig.amd.driversPage } else { "https://www.amd.com/en/support/download/drivers.html" }
                Start-Process $page
            }
            "3" {
                $guide = if ($GpuConfig -and $GpuConfig.amd.guideUrl) { $GpuConfig.amd.guideUrl } else { "$GuidesBaseUrl/amd-adrenalin.md" }
                Start-Process $guide
            }
            "4" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Open-NvidiaGpuMenu {
    param($GpuConfig)
    do {
        Clear-Host
        Write-Host "=== NVIDIA / NVCLEANSTALL ===" -ForegroundColor Green
        Write-Host "1. Ouvrir le guide NVCleanstall (GitHub)" -ForegroundColor Cyan
        Write-Host "2. Ouvrir la page drivers NVIDIA" -ForegroundColor White
        Write-Host "3. Ouvrir la page NVCleanstall" -ForegroundColor Yellow
        Write-Host "4. Installer NVCleanstall (winget)" -ForegroundColor Magenta
        Write-Host "5. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" {
                $guide = if ($GpuConfig -and $GpuConfig.nvidia.guideUrl) { $GpuConfig.nvidia.guideUrl } else { "$GuidesBaseUrl/nvidia-nvcleanstall.md" }
                Start-Process $guide
            }
            "2" {
                $page = if ($GpuConfig) { $GpuConfig.nvidia.driversPage } else { "https://www.nvidia.com/Download/index.aspx" }
                Start-Process $page
            }
            "3" {
                $page = if ($GpuConfig) { $GpuConfig.nvidia.nvcleanstallUrl } else { "https://www.techpowerup.com/download/techpowerup-nvcleanstall/" }
                Start-Process $page
            }
            "4" {
                winget install -e --id TechPowerUp.NVCleanstall --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
                Wait-ForUser
            }
            "5" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Import-GameModeCommon {
    try {
        $path = Get-FreshWindowsCachedScriptPath `
            -CacheFileName 'GameMode-Common.ps1' `
            -RemotePath 'scripts/GameMode-Common.ps1' `
            -RepoRawRoot $RepoRawRoot `
            -RepoRef $RepoRef `
            -FreshAppData $FreshAppData
        . $path -RepoRef $RepoRef
        return $true
    }
    catch {
        Write-Host "Impossible de charger GameMode-Common.ps1 : $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-GameModeKill {
    param([switch]$NoPause)

    Write-Host "`n=== MODE JEU — fermeture processus lourds ===" -ForegroundColor Red
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

    Write-Host "`nAstuce : raccourci Bureau « Mode Jeu » ou agent barre des tâches (menu 11)." -ForegroundColor DarkCyan
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
    $k.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$killStub`""
    $k.WorkingDirectory = $FreshAppData
    $k.Description = "Fresh Windows — mode jeu (liste générique)"
    if (Test-Path -LiteralPath $iconPath) { $k.IconLocation = "$iconPath,0" }
    $k.Save()
    Write-Host "→ Raccourci Bureau : Mode Jeu.lnk (sans admin)" -ForegroundColor Green

    if ($IncludeWatchAgent) {
        $startup = [Environment]::GetFolderPath('Startup')
        $lnkWatch = Join-Path $startup "Fresh Windows Surveillance.lnk"
        $w = $wsh.CreateShortcut($lnkWatch)
        $w.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $w.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchStub`""
        $w.WorkingDirectory = $FreshAppData
        $w.Description = "Agent Fresh Windows (CPU/RAM/disque/hang + toggle auto)"
        if (Test-Path -LiteralPath $iconPath) { $w.IconLocation = "$iconPath,0" }
        $w.Save()
        Write-Host "→ Démarrage Windows : Fresh Windows Surveillance.lnk" -ForegroundColor Green
        Write-Host "  Toggle « Détection auto » dans le menu clic droit de l'icône." -ForegroundColor DarkGray
    }

    if (-not $NoPause) { Wait-ForUser }
    return $true
}

function Open-GameModeSetupMenu {
    do {
        Clear-Host
        Write-Host "=== MODE JEU — raccourci & agent ===" -ForegroundColor Red
        Write-Host "Scripts copiés dans %LOCALAPPDATA%\FreshWindows (ref $RepoRef)." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "1. Raccourci Bureau « Mode Jeu » (sans admin)" -ForegroundColor Green
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

    $ok = Install-GameModeShortcuts -NoPause -IncludeWatchAgent:$false
    if (-not $ok) {
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }
    $stub = Join-Path $FreshAppData "Launch-GameModeWatch.ps1"
    if (-not (Test-Path -LiteralPath $stub)) {
        Write-Host "Stub agent introuvable." -ForegroundColor Red
        if (-not $NoPause) { Wait-ForUser }
        return $false
    }
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$stub`"" `
        -WorkingDirectory $FreshAppData
    Write-Host "Agent barre des tâches lancé (icône près de l'horloge)." -ForegroundColor Green
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
        Write-Host "`nÉchec — exit 1 (voir messages ci-dessus)." -ForegroundColor Red
        exit 1
    }
    Write-Host "`nOK — exit 0" -ForegroundColor Green
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
        $lnk.Description = "Fresh Windows (GitHub) — admin"
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
