#Requires -Version 5.1
<#
.SYNOPSIS
  Smoke tests des configs Fresh Windows (JSON + ShutUp10 cfg).
.DESCRIPTION
  A lancer depuis la racine du repo :
    powershell -NoProfile -File .\tests\Validate-Configs.ps1
  Exit 0 = OK, 1 = echec.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
$configs = Join-Path $root 'configs'
$failed = 0

function Fail([string]$msg) {
    Write-Host "FAIL  $msg" -ForegroundColor Red
    $script:failed++
}
function Ok([string]$msg) {
    Write-Host "OK    $msg" -ForegroundColor Green
}

Write-Host "Fresh Windows - validate configs" -ForegroundColor Cyan
Write-Host "Root : $root" -ForegroundColor DarkGray
Write-Host ""

$requiredJson = @(
    'apps-standard.json',
    'apps-gaming.json',
    'apps-dev.json',
    'extensions-firefox-based.json',
    'extensions-chrome-based.json',
    'game-mode-kill.json',
    'game-mode-watch.json',
    'gpu.json',
    'powertoys-profile.json',
    'winutil-appx.json',
    'winutil-oneclick.json',
    'winutil-brave-debloat.json'
)

foreach ($name in $requiredJson) {
    $path = Join-Path $configs $name
    if (-not (Test-Path -LiteralPath $path)) {
        Fail "$name manquant"
        continue
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $null = $raw | ConvertFrom-Json
        Ok "$name parse JSON"
    }
    catch {
        Fail ("{0} JSON invalide : {1}" -f $name, $_.Exception.Message)
    }
}

foreach ($appsFile in @('apps-standard.json', 'apps-gaming.json', 'apps-dev.json')) {
    $path = Join-Path $configs $appsFile
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $items = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $i = 0
    foreach ($item in @($items)) {
        $i++
        if ($item -is [string]) {
            if ([string]::IsNullOrWhiteSpace($item)) {
                Fail ("{0}[{1}] : id winget vide" -f $appsFile, $i)
            }
        }
        elseif ($item.url) {
            if ([string]::IsNullOrWhiteSpace([string]$item.url)) {
                Fail ("{0}[{1}] : objet sans url" -f $appsFile, $i)
            }
        }
        else {
            Fail ("{0}[{1}] : ni string ni objet .url" -f $appsFile, $i)
        }
    }
    Ok ("{0} ({1} entrees) structure OK" -f $appsFile, $i)
}

$ptPath = Join-Path $configs 'powertoys-profile.json'
if (Test-Path -LiteralPath $ptPath) {
    $pt = Get-Content -LiteralPath $ptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $pt.enabled) {
        Fail 'powertoys-profile.json : propriete enabled manquante'
    }
    else {
        Ok 'powertoys-profile.json enabled present'
    }
}

$cfgPath = Join-Path $configs 'shutup10-recommended.cfg'
if (-not (Test-Path -LiteralPath $cfgPath)) {
    Fail 'shutup10-recommended.cfg manquant'
}
else {
    $cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8
    if ($cfg -match '^\s*<\?xml' -or $cfg -match '<Settings\b') {
        Fail 'shutup10-recommended.cfg ressemble a du XML UI (non applyable en CLI)'
    }
    else {
        $lines = Get-Content -LiteralPath $cfgPath -Encoding UTF8 |
            Where-Object { $_ -and ($_ -notmatch '^\s*#') -and ($_ -notmatch '^\s*$') }
        $good = 0
        $bad = 0
        foreach ($line in $lines) {
            # SettingID + TAB + + ou -
            if ($line -match "^[^\t#][^\t]*\t[\+\-]\s*$") { $good++ }
            else { $bad++ }
        }
        if ($good -lt 10) {
            Fail ("shutup10-recommended.cfg : trop peu de lignes SettingID/TAB/+- (good={0})" -f $good)
        }
        elseif ($bad -gt 0) {
            Fail ("shutup10-recommended.cfg : {0} ligne(s) hors format (good={1})" -f $bad, $good)
        }
        else {
            Ok ("shutup10-recommended.cfg format CLI ({0} reglages)" -f $good)
        }
    }
}

$killPath = Join-Path $configs 'game-mode-kill.json'
if (Test-Path -LiteralPath $killPath) {
    $kill = Get-Content -LiteralPath $killPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $kill.domains) {
        Fail 'game-mode-kill.json : propriete domains manquante (liste generique)'
    }
    elseif (-not $kill.protect) {
        Fail 'game-mode-kill.json : propriete protect manquante'
    }
    elseif (-not $kill.gaming_launchers) {
        Fail 'game-mode-kill.json : gaming_launchers manquant'
    }
    else {
        $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($prop in $kill.domains.PSObject.Properties) {
            foreach ($n in @($prop.Value)) {
                if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$names.Add($n.Trim()) }
            }
        }
        $prot = 0
        foreach ($prop in $kill.protect.PSObject.Properties) {
            foreach ($n in @($prop.Value)) { if ($n) { $prot++ } }
        }
        $launchers = @($kill.gaming_launchers | Where-Object { $_ })
        if ($names.Count -lt 5) {
            Fail ("game-mode-kill.json : trop peu de process dans domains ({0})" -f $names.Count)
        }
        elseif ($prot -lt 3) {
            Fail 'game-mode-kill.json : protect.communication trop courte'
        }
        elseif ($launchers.Count -lt 3) {
            Fail 'game-mode-kill.json : gaming_launchers trop courte'
        }
        else {
            Ok ("game-mode-kill.json ({0} kill, {1} comm protect, {2} launchers)" -f $names.Count, $prot, $launchers.Count)
        }
    }
}

$gpuPath = Join-Path $configs 'gpu.json'
if (Test-Path -LiteralPath $gpuPath) {
    $gpu = Get-Content -LiteralPath $gpuPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($key in @('amd', 'nvidia')) {
        $node = $gpu.$key
        if (-not $node) {
            Fail ("gpu.json : cle {0} manquante" -f $key)
            continue
        }
    }
    Ok 'gpu.json cles amd/nvidia presentes'
}

Write-Host ""
if ($failed -gt 0) {
    Write-Host ("{0} echec(s)" -f $failed) -ForegroundColor Red
    exit 1
}
Write-Host "Tous les tests configs OK." -ForegroundColor Green
exit 0
