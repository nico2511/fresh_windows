#Requires -Version 5.1
<#
  Valide registry.json : fichiers skills presents, ids coherents.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
$configs = Join-Path $root 'configs'
$regPath = Join-Path $configs 'skills\registry.json'
$failed = 0

function Fail([string]$msg) {
    Write-Host "FAIL  $msg" -ForegroundColor Red
    $script:failed++
}
function Ok([string]$msg) {
    Write-Host "OK    $msg" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $regPath)) {
    Fail 'registry.json introuvable'
    exit 1
}

$reg = Get-Content -LiteralPath $regPath -Raw -Encoding UTF8 | ConvertFrom-Json
$seen = @{}
foreach ($entry in @($reg.skills)) {
    if (-not $entry.id) { Fail 'entree skill sans id'; continue }
    if ($seen.ContainsKey($entry.id)) { Fail ("id duplique: {0}" -f $entry.id) }
    $seen[$entry.id] = $true
    if (-not $entry.file) { Fail ("{0}: file manquant" -f $entry.id); continue }
    $skillPath = Join-Path $configs ('skills\' + ($entry.file -replace '/', '\'))
    if (-not (Test-Path -LiteralPath $skillPath)) {
        Fail ("{0}: fichier absent ({1})" -f $entry.id, $entry.file)
        continue
    }
    $def = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($def.id -ne $entry.id) {
        Fail ("{0}: id JSON ({1}) != registry ({2})" -f $entry.file, $def.id, $entry.id)
    }
    if ([string]::IsNullOrWhiteSpace($def.handler)) {
        Fail ("{0}: handler manquant" -f $entry.id)
    }
}

if ($failed -eq 0) {
    Ok ("registry.json ({0} skills)" -f $seen.Count)
}
exit $failed
