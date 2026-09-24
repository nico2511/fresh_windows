#Requires -Version 5.1
<#
.SYNOPSIS
  Copie le clone Git local vers %LOCALAPPDATA%\FreshWindows (dev / test sans GitHub).
.PARAMETER RepoRoot
  Racine du depot (defaut : parent du dossier scripts).
.PARAMETER FreshAppData
  Cible agent (defaut FreshWindows AppData).
#>
param(
    [string]$RepoRoot = '',
    [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows')
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$scriptsSrc = Join-Path $RepoRoot 'scripts'
$configsSrc = Join-Path $RepoRoot 'configs'

if (-not (Test-Path -LiteralPath $scriptsSrc)) {
    throw "Dossier scripts introuvable : $scriptsSrc"
}

New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null

foreach ($name in @(
        'GameMode-Common.ps1', 'Invoke-GameModeKill.ps1', 'GameMode-WatchAgent.ps1',
        'Stop-FreshWatchAgent.ps1', 'Sync-FreshWindowsAgent.ps1', 'Dev-SyncFreshAgentFromRepo.ps1'
    )) {
    $src = Join-Path $scriptsSrc $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $FreshAppData $name) -Force
        Write-Host "-> $name" -ForegroundColor DarkGray
    }
}

foreach ($sub in @('lib', 'ai')) {
    $from = Join-Path $scriptsSrc $sub
    if (-not (Test-Path -LiteralPath $from)) { continue }
    $to = Join-Path $FreshAppData $sub
    New-Item -ItemType Directory -Path $to -Force | Out-Null
    Get-ChildItem -LiteralPath $from -Force | Copy-Item -Destination $to -Recurse -Force
    Write-Host "-> $sub\*" -ForegroundColor DarkGray
}

if (Test-Path -LiteralPath $configsSrc) {
    $cfgDest = Join-Path $FreshAppData 'configs'
    New-Item -ItemType Directory -Path $cfgDest -Force | Out-Null
    Get-ChildItem -LiteralPath $configsSrc -Force | Copy-Item -Destination $cfgDest -Recurse -Force
    Write-Host '-> configs\*' -ForegroundColor DarkGray
}

$configLib = Join-Path $FreshAppData 'lib\FreshAgent-Config.ps1'
if (-not (Test-Path -LiteralPath $configLib)) {
    throw 'FreshAgent-Config.ps1 manquant apres copie.'
}
. $configLib

Get-ChildItem -LiteralPath $FreshAppData -Recurse -Filter '*.ps1' -File | ForEach-Object {
    Set-FreshScriptUtf8Bom -Path $_.FullName
}

$coreLib = Join-Path $scriptsSrc 'lib\Launcher-Core.ps1'
. $coreLib
Publish-FreshGameModeWatchStubs -FreshAppData $FreshAppData | Out-Null

Set-Content -LiteralPath (Join-Path $FreshAppData 'scripts.ref') -Value 'local-dev' -Encoding UTF8 -NoNewline

Write-Host ""
Write-Host "Dev sync OK : $FreshAppData" -ForegroundColor Green
Write-Host "Tests parse : powershell -NoProfile -ExecutionPolicy Bypass -File `"$RepoRoot\tests\Parse-Scripts.ps1`"" -ForegroundColor Cyan
Write-Host "Agent       : & `"$FreshAppData\Start-WatchAgent.cmd`"" -ForegroundColor Cyan
