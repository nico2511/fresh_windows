#Requires -Version 5.1
<#
  WinUtil (Chris Titus) + O&O ShutUp10 + maintenance hebdo.
  Utilise $BaseUrl, $RepoRef, $FreshAppData du launcher parent.
#>
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
