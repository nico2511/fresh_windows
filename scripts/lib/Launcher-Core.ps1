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
`$env:FRESH_WIN_REF = '$Ref'
& '$FreshAppData\GameMode-WatchAgent.ps1'
"@ | Set-Content -LiteralPath $watchStub -Encoding UTF8

    return $true
}
