#Requires -Version 5.1
<#
  Fonctions partagées Fresh Windows (launcher irm, clone local, tâches planifiées).
  Dot-sourcé depuis launcher.ps1 - utilise $RepoRef, $RepoRawRoot, $LauncherUrl, $FreshAppData du parent.
#>

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
    return $stubPath
}

function Start-FreshWindowsUnelevated {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$WorkingDirectory = ''
    )

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = Split-Path -Parent $FilePath
    }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'powershell' -and $_.CommandLine -match 'GameMode-WatchAgent|Launch-GameModeWatch|Start-WatchAgent' } |
        ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }

    $cmdPath = Join-Path $WorkingDirectory 'Start-WatchAgent.cmd'
    if (-not (Test-Path -LiteralPath $cmdPath)) {
        throw "Start-WatchAgent.cmd introuvable (menu 11 d'abord)."
    }

    # Un seul argument : le .cmd (pas de quotes PowerShell imbriquees)
    Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" `
        -ArgumentList "/trustlevel:0x20000 `"$cmdPath`"" `
        -WorkingDirectory $WorkingDirectory
    Start-Sleep -Seconds 1

    $alive = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'Launch-GameModeWatch|GameMode-WatchAgent|Start-WatchAgent' }
    if (-not $alive) {
        Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList "`"$cmdPath`""
    }
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

    foreach ($scriptName in @('GameMode-Common.ps1', 'Invoke-GameModeKill.ps1', 'GameMode-WatchAgent.ps1')) {
        $dest = Join-Path $FreshAppData $scriptName
        $url  = "$RepoRawRoot/scripts/$scriptName"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        if (Get-Command ConvertTo-Utf8BomFile -ErrorAction SilentlyContinue) {
            ConvertTo-Utf8BomFile -Path $dest
        }
        Write-Host "-> $scriptName" -ForegroundColor DarkGray
    }

    Set-Content -LiteralPath (Join-Path $FreshAppData 'scripts.ref') -Value $Ref -Encoding UTF8 -NoNewline

    $killStub = Join-Path $FreshAppData "Launch-GameModeKill.ps1"
    @"
#Requires -Version 5.1
`$env:FRESH_WIN_REF = '$Ref'
`$env:FRESH_WIN_NO_PAUSE = '1'
& '$FreshAppData\Invoke-GameModeKill.ps1'
"@ | Set-Content -LiteralPath $killStub -Encoding UTF8

    $watchStub = Join-Path $FreshAppData "Launch-GameModeWatch.ps1"
    @"
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$env:FRESH_WIN_REF = '$Ref'
`$log = Join-Path `$PSScriptRoot 'watch-agent.log'
Set-Content -LiteralPath `$log -Value ((Get-Date -Format o) + ' stub start') -Encoding UTF8
try {
    & (Join-Path `$PSScriptRoot 'GameMode-WatchAgent.ps1')
}
catch {
    Add-Content -LiteralPath `$log -Value (`$_ | Out-String) -Encoding UTF8
    Write-Host (`$_ | Out-String) -ForegroundColor Red
    Read-Host 'Erreur agent - Entree pour fermer (voir watch-agent.log)'
    throw
}
"@ | Set-Content -LiteralPath $watchStub -Encoding UTF8

    $cmdPath = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
    @"
@echo off
cd /d "%~dp0"
echo %DATE% %TIME% cmd start>> "%~dp0watch-agent.log"
title Fresh Windows Watch
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Launch-GameModeWatch.ps1"
if errorlevel 1 pause
"@ | Set-Content -LiteralPath $cmdPath -Encoding ASCII

    return $true
}
