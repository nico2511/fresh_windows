#Requires -Version 5.1
<#
.SYNOPSIS
  Sync complet agent Fresh Windows (mode jeu + Fresh Agent) vers %LOCALAPPDATA%\FreshWindows.
.PARAMETER RepoRef
  Branche / commit GitHub (defaut: scripts.ref, FRESH_WIN_REF ou main).
#>
param(
    [string]$RepoRef = ''
)

$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
catch { }

$FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($RepoRef)) {
    $refFile = Join-Path $FreshAppData 'scripts.ref'
    if ($env:FRESH_WIN_REF) {
        $RepoRef = $env:FRESH_WIN_REF.Trim()
    }
    elseif (Test-Path -LiteralPath $refFile) {
        $RepoRef = (Get-Content -LiteralPath $refFile -Raw -Encoding UTF8).Trim()
    }
    else {
        $RepoRef = 'main'
    }
}

$RepoRawRoot = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef"

foreach ($scriptName in @('GameMode-Common.ps1', 'Invoke-GameModeKill.ps1', 'GameMode-WatchAgent.ps1')) {
    $dest = Join-Path $FreshAppData $scriptName
    $url = "$RepoRawRoot/scripts/$scriptName"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

$configLib = Join-Path $FreshAppData 'lib\FreshAgent-Config.ps1'
$configUrl = "$RepoRawRoot/scripts/lib/FreshAgent-Config.ps1"
New-Item -ItemType Directory -Path (Split-Path $configLib -Parent) -Force | Out-Null
Invoke-WebRequest -Uri $configUrl -OutFile $configLib -UseBasicParsing
. $configLib

$logLib = Join-Path $FreshAppData 'lib\FreshAgent-Log.ps1'
try {
    Invoke-WebRequest -Uri "$RepoRawRoot/scripts/lib/FreshAgent-Log.ps1" -OutFile $logLib -UseBasicParsing
    . $logLib
}
catch { }

Sync-FreshAgentLocalAssets -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $RepoRef | Out-Null
Set-Content -LiteralPath (Join-Path $FreshAppData 'scripts.ref') -Value $RepoRef -Encoding UTF8 -NoNewline

if (Get-Command Write-FreshAgentLog -ErrorAction SilentlyContinue) {
    Write-FreshAgentLog -Category 'Sync' -Message "Sync-FreshWindowsAgent.ps1 termine (ref $RepoRef)" -FreshAppData $FreshAppData
}

Write-Host "Sync Fresh Agent OK (ref $RepoRef) -> $FreshAppData" -ForegroundColor Green
