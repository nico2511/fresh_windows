#Requires -RunAsAdministrator
# ============================================================
#  TOOLBOX REINSTALL WINDOWS 
#  Listes toujours lues depuis GitHub (édition à distance)
#
#  Modes non interactifs (sans menu) :
#    $env:FRESH_WIN_MODE='full'; irm ... | iex
#    Modes apps : standard | gaming | dev | full
#    Modes WinUtil : winutil-oneclick | winutil-standard | winutil-minimal | winutil-advanced | winutil-appx
#    Autre : winget-task | tasks (crée toutes les tâches planifiées)
# ============================================================

# Via env (compatible irm | iex) — pas de param() qui casse le pipe
$Mode = if ($env:FRESH_WIN_MODE) { $env:FRESH_WIN_MODE.Trim().ToLowerInvariant() } else { 'menu' }

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "Toolbox AMD Gamer + Cursor"

# TLS 1.2 requis sur certaines machines / vieux PowerShell
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Source unique : listes JSON sur GitHub (pas de configs locales)
$BaseUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/main/configs"
$GuidesBaseUrl = "https://github.com/nico2511/fresh_windows/blob/main/guides"
$LauncherUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1"

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
    try { $Host.UI.RawUI.WindowTitle = "Toolbox [$Current/$Total] $Category — $App" } catch { }
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

function Install-AppEntry {
    param($App)

    if ($App -is [string]) {
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
        if (-not $NoPause) { Pause }
        return $false
    }

    Write-Host "  Exe : $exe" -ForegroundColor DarkGray

    # Free v3 : pas de vrai CLI « apply recommended » documenté (Premium = protection auto).
    # On tente un import silencieux SI un profil .cfg est hébergé sur le repo.
    $cfgUrl = "$BaseUrl/shutup10-recommended.cfg"
    $cfgLocal = Join-Path $env:TEMP "fresh_windows-shutup10-recommended.cfg"
    $cfgOk = $false
    try {
        Invoke-WebRequest -Uri $cfgUrl -OutFile $cfgLocal -UseBasicParsing -ErrorAction Stop
        if ((Test-Path $cfgLocal) -and ((Get-Item $cfgLocal).Length -gt 100)) {
            # Legacy quiet apply (v1/v2 et parfois encore accepté)
            Write-Host "  → Tentative d'import silencieux du profil GitHub..." -ForegroundColor Yellow
            $p = Start-Process -FilePath $exe -ArgumentList @("`"$cfgLocal`"", "/quiet") -PassThru -Wait -WindowStyle Hidden
            if ($p.ExitCode -eq 0) {
                Write-Host "  Profil appliqué via /quiet." -ForegroundColor Green
                $cfgOk = $true
            }
            else {
                Write-Host "  /quiet non supporté ou échec (code $($p.ExitCode)) — ouverture GUI." -ForegroundColor DarkYellow
            }
        }
    }
    catch {
        Write-Host "  Pas de configs/shutup10-recommended.cfg sur GitHub (normal pour l'instant)." -ForegroundColor DarkGray
    }

    if ($LaunchGui) {
        Write-Host ""
        Write-Host "  Free ShutUp10++ : applique le profil recommandé dans l'UI :" -ForegroundColor Yellow
        Write-Host "    Actions → Appliquer tous les paramètres recommandés" -ForegroundColor White
        Write-Host "  (crée un point de restauration — c'est normal)" -ForegroundColor DarkGray
        Write-Host "  Premium = ré-application auto après Windows Update." -ForegroundColor DarkGray
        Write-Host ""
        Start-Process -FilePath $exe
    }
    elseif (-not $cfgOk) {
        if ($NoPause) {
            Write-Host "  Mode silencieux : pas de .cfg GitHub — ShutUp10 ignoré (pas de GUI)." -ForegroundColor DarkYellow
            Write-Host "  Dépose configs/shutup10-recommended.cfg pour l'auto-apply hebdo." -ForegroundColor DarkGray
        }
        else {
            Write-Host ""
            Write-Host "  Free ShutUp10++ : applique le profil recommandé dans l'UI :" -ForegroundColor Yellow
            Write-Host "    Actions → Appliquer tous les paramètres recommandés" -ForegroundColor White
            Write-Host ""
            Start-Process -FilePath $exe
        }
    }

    if (-not $NoPause) { Pause }
    return ($cfgOk -or $LaunchGui -or -not $NoPause)
}

function Invoke-MaintenanceReapply {
    param([switch]$NoPause)

    Write-Host "`n=== MAINTENANCE HEBDO : WinUtil + ShutUp10 ===" -ForegroundColor Cyan
    Invoke-WinUtilOneClick -NoPause
    Invoke-ShutUp10Recommended -NoPause
    Write-Host "`nMaintenance terminée." -ForegroundColor Green
    if (-not $NoPause) { Pause }
}

function Install-FromJson {
    param(
        [string]$FileName,
        [string]$Category,
        [switch]$NoPause
    )
    $apps = Get-Config -FileName $FileName
    if (-not $apps) {
        if (-not $NoPause) { Pause }
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
    try { $Host.UI.RawUI.WindowTitle = "Toolbox AMD Gamer + Cursor" } catch { }

    if ($failed.Count -gt 0) {
        Write-Host "`nÉchecs ($Category) : $($failed -join ', ')" -ForegroundColor Red
    }
    else {
        Write-Host "`nCatégorie $Category terminée. [$total/$total]" -ForegroundColor Green
    }

    if (-not $NoPause) { Pause }
    return ($failed.Count -eq 0)
}

function Open-Extensions {
    Clear-Host
    Write-Host "=== EXTENSIONS NAVIGATEUR ===" -ForegroundColor Cyan
    Write-Host "1. Firefox-based (Zen, Firefox...) - Recommandé"
    Write-Host "2. Chrome-based (Brave, Chrome, Edge...)"
    Write-Host "3. Retour"
    $c = Read-Host "Choix"

    switch ($c) {
        "1" {
            $urls = Get-Config -FileName "extensions-firefox-based.json"
            if (-not $urls) { Pause; return }
            Write-Host "`nOuverture des extensions Firefox-based..." -ForegroundColor Yellow
            foreach ($url in $urls) {
                if ($url -notmatch '^https?://') {
                    Write-Host "  URL ignorée (schéma non http/https) : $url" -ForegroundColor DarkYellow
                    continue
                }
                Start-Process $url
            }
            Write-Host "Pages ouvertes (vrai uBlock Origin)." -ForegroundColor Green
            Pause
        }
        "2" {
            $urls = Get-Config -FileName "extensions-chrome-based.json"
            if (-not $urls) { Pause; return }
            Write-Host "`nOuverture des extensions Chrome-based..." -ForegroundColor Yellow
            foreach ($url in $urls) {
                if ($url -notmatch '^https?://') {
                    Write-Host "  URL ignorée (schéma non http/https) : $url" -ForegroundColor DarkYellow
                    continue
                }
                Start-Process $url
            }
            Write-Host "Pages ouvertes." -ForegroundColor Green
            Pause
        }
        "3" { return }
        default {
            Write-Host "Choix invalide" -ForegroundColor Red
            Start-Sleep 1
        }
    }
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

    try {
        Write-Host "`n[1/3] WinUtil : Standard + AppX (safe) + Hyper-V..." -ForegroundColor Yellow
        & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Config $configUrl

        Write-Host "`n[2/3] Customize Preferences..." -ForegroundColor Yellow
        Invoke-WinUtilPreferences

        Write-Host "`n[3/3] Mode Performance..." -ForegroundColor Yellow
        Enable-UltimatePerformance

        Write-Host "`nProfil one-click terminé. Un redémarrage peut être requis (Hyper-V)." -ForegroundColor Green
    }
    catch {
        Write-Host "Échec du profil one-click" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }

    if (-not $NoPause) { Pause }
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
    try {
        & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Config $ConfigUrl
        Write-Host "`n$Label terminé." -ForegroundColor Green
    }
    catch {
        Write-Host "Échec WinUtil $Label" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
    if (-not $NoPause) { Pause }
}

function Invoke-WinUtilPreset {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Standard', 'Minimal', 'Advanced')]
        [string]$Preset
    )

    Write-Host "`n→ WinUtil preset '$Preset' (sans UI)..." -ForegroundColor Yellow
    Write-Host "  Source : https://christitus.com/win" -ForegroundColor DarkGray
    try {
        & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Preset $Preset
        Write-Host "`nPreset '$Preset' terminé." -ForegroundColor Green
    }
    catch {
        Write-Host "Échec WinUtil preset '$Preset'" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
    Pause
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

function Show-Menu {
    Clear-Host
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "       TOOLBOX AMD GAMER + CURSOR (GitHub)" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "Configs : $BaseUrl" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "1. Installer Apps Standard" -ForegroundColor Green
    Write-Host "2. Installer Apps Gaming" -ForegroundColor Magenta
    Write-Host "3. Installer Apps Dev" -ForegroundColor Blue
    Write-Host "4. Full Setup (Standard + Gaming + Dev)" -ForegroundColor Cyan
    Write-Host "5. Extensions Navigateur (Firefox / Chrome-based)" -ForegroundColor Yellow
    Write-Host "6. Mettre à jour toutes les apps (winget upgrade --all)" -ForegroundColor White
    Write-Host "7. WinUtil — one-click / presets / GUI" -ForegroundColor Gray
    Write-Host "8. Tâches planifiées (tout activer en 1 clic)" -ForegroundColor DarkCyan
    Write-Host "9. Carte graphique (AMD / NVIDIA)" -ForegroundColor DarkYellow
    Write-Host "10. Mode Jeu — kill process dev" -ForegroundColor Red
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
        if (-not $NoPause) { Pause }
        return $false
    }

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $settings  = Get-CommonTaskSettings -Hours 3
    $ok = $true

    Write-Host "`n→ Création des tâches planifiées (une fois)..." -ForegroundColor Cyan

    # 1) Winget quotidien 12:00 + rattrapage
    try {
        $wingetCmd = 'winget source update --disable-interactivity; winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity'
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
    try {
        $maintInner = "`$env:FRESH_WIN_MODE='maintenance'; irm '$LauncherUrl' | iex"
        $maintArg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"$maintInner`""
        $maintAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $maintArg
        $maintTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "12:00"

        Register-ScheduledTask `
            -TaskName $script:WinUtilReapplyTaskName `
            -Action $maintAction `
            -Trigger $maintTrigger `
            -Settings $settings `
            -Principal $principal `
            -Description "Fresh Windows: WinUtil one-click + ShutUp10 (StartWhenAvailable)." `
            -Force -ErrorAction Stop | Out-Null

        Write-Host "  [OK] $script:WinUtilReapplyTaskName — dimanche 12:00 (+ rattrapage)" -ForegroundColor Green
        Write-Host "       WinUtil one-click + ShutUp10 (cfg silencieux si présent)" -ForegroundColor DarkGray
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

    if (-not $NoPause) { Pause }
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
    if (-not $NoPause) { Pause }
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
                Pause
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
                Pause
            }
            "5" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Invoke-GameModeKill {
    param([switch]$NoPause)

    Write-Host "`n=== MODE JEU — kill process dev ===" -ForegroundColor Red
    Write-Host "Ferme les apps lourdes de dev / navigateur pour libérer RAM/CPU/GPU." -ForegroundColor DarkGray

    $list = Get-Config -FileName "game-mode-kill.json"
    if (-not $list) {
        if (-not $NoPause) { Pause }
        return
    }

    # Ne jamais tuer le shell courant
    $selfPid = $PID
    $killed = @()
    $skipped = @()

    foreach ($name in $list) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $selfPid }
        if (-not $procs) { continue }

        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                $killed += "$($p.ProcessName) ($($p.Id))"
            }
            catch {
                $skipped += "$($p.ProcessName) ($($p.Id))"
            }
        }
    }

    if ($killed.Count -gt 0) {
        Write-Host "`nTués ($($killed.Count)) :" -ForegroundColor Green
        $killed | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    }
    else {
        Write-Host "`nAucun process de la liste n'était ouvert." -ForegroundColor Yellow
    }
    if ($skipped.Count -gt 0) {
        Write-Host "Ignorés / protégés :" -ForegroundColor DarkYellow
        $skipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
    }

    Write-Host "`nAstuce : active aussi le plan Ultimate Performance (menu WinUtil one-click)." -ForegroundColor DarkCyan
    if (-not $NoPause) { Pause }
}

function Invoke-SilentMode {
    param([string]$InstallMode)

    Write-Host "Mode silencieux : $InstallMode" -ForegroundColor Cyan
    switch ($InstallMode) {
        "standard" {
            Install-FromJson -FileName "apps-standard.json" -Category "Standard" -NoPause | Out-Null
        }
        "gaming" {
            Install-FromJson -FileName "apps-gaming.json" -Category "Gaming" -NoPause | Out-Null
        }
        "dev" {
            Install-FromJson -FileName "apps-dev.json" -Category "Dev" -NoPause | Out-Null
        }
        "full" {
            Install-FromJson -FileName "apps-standard.json" -Category "Standard" -NoPause | Out-Null
            Install-FromJson -FileName "apps-gaming.json" -Category "Gaming" -NoPause | Out-Null
            Install-FromJson -FileName "apps-dev.json" -Category "Dev" -NoPause | Out-Null
            Write-Host "`nFull Setup terminé !" -ForegroundColor Green
        }
        "winutil-oneclick" {
            Invoke-WinUtilOneClick -NoPause
        }
        "maintenance" {
            Invoke-MaintenanceReapply -NoPause
        }
        "winutil-standard" {
            & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Preset Standard
        }
        "winutil-minimal" {
            & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Preset Minimal
        }
        "winutil-advanced" {
            & ([ScriptBlock]::Create((Invoke-RestMethod -Uri "https://christitus.com/win" -UseBasicParsing))) -Preset Advanced
        }
        "winutil-appx" {
            Invoke-WinUtilConfig -ConfigUrl "$BaseUrl/winutil-appx.json" -Label "AppX bloat" -NoPause
        }
        "winget-task" {
            Register-AllScheduledTasks -NoPause | Out-Null
        }
        "winutil-task" {
            Register-AllScheduledTasks -NoPause | Out-Null
        }
        "tasks" {
            Register-AllScheduledTasks -NoPause | Out-Null
        }
        "game-mode" {
            Invoke-GameModeKill -NoPause
        }
        "powertoys-profile" {
            Apply-PowerToysProfile | Out-Null
        }
        "shutup10" {
            Invoke-ShutUp10Recommended -LaunchGui -NoPause
        }
        default {
            Write-Host "Mode inconnu : $InstallMode" -ForegroundColor Red
            exit 1
        }
    }
    exit 0
}

# ========== ENTRÉE ==========
if ($Mode -ne 'menu') {
    Invoke-SilentMode -InstallMode $Mode
}

do {
    Show-Menu
    $choice = Read-Host "Ton choix"

    switch ($choice) {
        "1" { Install-FromJson -FileName "apps-standard.json" -Category "Standard" | Out-Null }
        "2" { Install-FromJson -FileName "apps-gaming.json" -Category "Gaming" | Out-Null }
        "3" { Install-FromJson -FileName "apps-dev.json" -Category "Dev" | Out-Null }
        "4" {
            Install-FromJson -FileName "apps-standard.json" -Category "Standard" -NoPause | Out-Null
            Install-FromJson -FileName "apps-gaming.json" -Category "Gaming" -NoPause | Out-Null
            Install-FromJson -FileName "apps-dev.json" -Category "Dev" -NoPause | Out-Null
            Write-Host "`nFull Setup terminé !" -ForegroundColor Green
            Pause
        }
        "5" { Open-Extensions }
        "6" {
            winget source update --disable-interactivity
            winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
            Pause
        }
        "7" { Open-WinUtilMenu }
        "8" { Open-ScheduledTasksMenu }
        "9" { Open-GpuMenu }
        "10" { Invoke-GameModeKill }
        "0" { exit }
        default {
            Write-Host "Choix invalide" -ForegroundColor Red
            Start-Sleep 1
        }
    }
} while ($true)
