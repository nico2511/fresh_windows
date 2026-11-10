#Requires -Version 5.1
<#
.SYNOPSIS
  Sync scripts mode jeu + maintenance vers %LOCALAPPDATA%\FreshWindows.
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

function Set-FreshScriptUtf8Bom {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return
    }
    $needsBom = $false
    foreach ($b in $bytes) {
        if ($b -gt 127) { $needsBom = $true; break }
    }
    if (-not $needsBom) { return }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $text = $utf8NoBom.GetString($bytes)
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $text, $utf8Bom)
}

$coreLib = Join-Path $FreshAppData 'Launcher-Core.ps1'
$coreUrl = "$RepoRawRoot/scripts/lib/Launcher-Core.ps1"
try {
    Invoke-WebRequest -Uri $coreUrl -OutFile $coreLib -UseBasicParsing
    Set-FreshScriptUtf8Bom -Path $coreLib
    . $coreLib
    Sync-GameModeLocalScripts -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $RepoRef | Out-Null
}
catch {
    Write-Host "!! Sync local partiel : $($_.Exception.Message)" -ForegroundColor Yellow
    foreach ($scriptName in @(
            'GameMode-Common.ps1',
            'Invoke-GameModeKill.ps1',
            'Sync-FreshWindowsAgent.ps1',
            'Invoke-FreshWindowsBackgroundAudit.ps1'
        )) {
        $dest = Join-Path $FreshAppData $scriptName
        $url = "$RepoRawRoot/scripts/$scriptName"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Set-FreshScriptUtf8Bom -Path $dest
    }
    Set-Content -LiteralPath (Join-Path $FreshAppData 'scripts.ref') -Value $RepoRef -Encoding UTF8 -NoNewline
}

Write-Host "Sync Fresh Windows OK (ref $RepoRef) -> $FreshAppData" -ForegroundColor Green
