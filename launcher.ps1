#Requires -RunAsAdministrator
# ============================================================
#  TOOLBOX AMD GAMER + CURSOR - Launcher
#  Listes toujours lues depuis GitHub (édition à distance)
# ============================================================

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "Toolbox AMD Gamer + Cursor"

# TLS 1.2 requis sur certaines machines / vieux PowerShell
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Source unique : listes JSON sur GitHub (pas de configs locales)
$BaseUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/main/configs"

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

    Write-Host "`n→ Installation de la catégorie : $Category" -ForegroundColor Yellow
    $failed = @()
    foreach ($app in $apps) {
        if ([string]::IsNullOrWhiteSpace($app)) { continue }
        Write-Host "  → $app" -ForegroundColor Gray
        winget install -e --id $app --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
        # 0 = OK, -1978335189 (0x8A15002B) = déjà installé
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
            Write-Host "    Échec (code $LASTEXITCODE)" -ForegroundColor Red
            $failed += $app
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host "`nÉchecs ($Category) : $($failed -join ', ')" -ForegroundColor Red
    }
    else {
        Write-Host "`nCatégorie $Category terminée." -ForegroundColor Green
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
    Write-Host "7. Lancer WinUtil" -ForegroundColor Gray
    Write-Host "0. Quitter" -ForegroundColor Red
    Write-Host ""
}

# ========== BOUCLE PRINCIPALE ==========
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
            winget upgrade --all --accept-package-agreements --accept-source-agreements
            Pause
        }
        "7" {
            Write-Host "Téléchargement et exécution de WinUtil (christitus.com)..." -ForegroundColor Yellow
            irm "https://christitus.com/win" | iex
        }
        "0" { exit }
        default {
            Write-Host "Choix invalide" -ForegroundColor Red
            Start-Sleep 1
        }
    }
} while ($true)
