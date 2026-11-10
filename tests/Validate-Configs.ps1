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
    'gpu.json',
    'powertoys-profile.json',
    'winutil-appx.json',
    'winutil-oneclick.json',
    'winutil-brave-debloat.json',
    'brave-optimize.json',
    'appx-bloatware.json',
    'game-mode-watch.json',
    'maintenance-content.json'
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

$customDir = Join-Path $configs 'apps-custom'
if (-not (Test-Path -LiteralPath $customDir)) {
    Fail 'apps-custom/ manquant'
}
else {
    Ok 'apps-custom/ present'
    Get-ChildItem -LiteralPath $customDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $appsFile = "apps-custom/$($_.Name)"
            try {
                $items = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            catch {
                Fail ("{0} JSON invalide : {1}" -f $appsFile, $_.Exception.Message)
                return
            }
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
    else {
        $hasFlat = $kill.gaming_launchers -and (@($kill.gaming_launchers).Count -gt 0)
        $hasFamilies = $kill.gaming_launcher_families -and ($kill.gaming_launcher_families.PSObject.Properties.Count -gt 0)
        if (-not $hasFlat -and -not $hasFamilies) {
            Fail 'game-mode-kill.json : gaming_launchers ou gaming_launcher_families manquant'
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
            $launcherCount = 0
            if ($hasFamilies) {
                foreach ($prop in $kill.gaming_launcher_families.PSObject.Properties) {
                    $launcherCount += @($prop.Value).Count
                }
            }
            elseif ($hasFlat) {
                $launcherCount = @($kill.gaming_launchers | Where-Object { $_ }).Count
            }
            if ($names.Count -lt 5) {
                Fail ("game-mode-kill.json : trop peu de process dans domains ({0})" -f $names.Count)
            }
            elseif ($prot -lt 3) {
                Fail 'game-mode-kill.json : protect.communication trop courte'
            }
            elseif ($launcherCount -lt 3) {
                Fail 'game-mode-kill.json : trop peu de launchers'
            }
            elseif (-not $names.Contains('Bitwarden')) {
                Fail 'game-mode-kill.json : Bitwarden manquant dans domains'
            }
            elseif (-not $kill.protect.ai_runtime) {
                Fail 'game-mode-kill.json : protect.ai_runtime manquant'
            }
            else {
                $aiLocal = @()
                if ($kill.domains.ai_local) { $aiLocal = @($kill.domains.ai_local) }
                $hasOllamaKill = ($aiLocal | Where-Object { $_ -match '^(?i)ollama$' }).Count -gt 0
                $aiProt = @($kill.protect.ai_runtime | Where-Object { $_ })
                $ollamaProtected = ($aiProt | Where-Object { $_ -match 'ollama' }).Count -gt 0
                if (-not $hasOllamaKill) {
                    Fail 'game-mode-kill.json : ollama manquant dans domains.ai_local (ferme en mode jeu)'
                }
                if ($ollamaProtected) {
                    Fail 'game-mode-kill.json : ollama ne doit pas etre dans protect.ai_runtime (incoherent avec mode jeu)'
                }
                Ok ("game-mode-kill.json ({0} kill, {1} protect entries, {2} launcher names)" -f $names.Count, $prot, $launcherCount)
            }
        }
    }
}

$bloatPath = Join-Path $configs 'appx-bloatware.json'
if (Test-Path -LiteralPath $bloatPath) {
    $bw = Get-Content -LiteralPath $bloatPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $bw.protected -or -not $bw.remove) {
        Fail 'appx-bloatware.json : protected ou remove manquant'
    }
    elseif (-not ($bw.protected.exact -contains 'Microsoft.Paint')) {
        Fail 'appx-bloatware.json : Microsoft.Paint doit etre protege'
    }
    elseif (-not ($bw.remove.exact -contains 'Microsoft.MSPaint')) {
        Fail 'appx-bloatware.json : Microsoft.MSPaint (Paint 3D) doit etre en remove'
    }
    elseif (-not ($bw.remove.exact -contains 'Microsoft.XboxGamingOverlay')) {
        Fail 'appx-bloatware.json : Microsoft.XboxGamingOverlay doit rester en remove'
    }
    elseif (-not ($bw.protected.exact -contains 'Microsoft.GamingApp')) {
        Fail 'appx-bloatware.json : Microsoft.GamingApp (Xbox PC) doit etre protege'
    }
    elseif (-not ($bw.protected.exact -contains 'Microsoft.GamingServices')) {
        Fail 'appx-bloatware.json : Microsoft.GamingServices doit etre protege'
    }
    elseif (-not $bw.confirmLater -or $null -eq $bw.confirmLater.exact) {
        Fail 'appx-bloatware.json : confirmLater ou confirmLater.exact manquant'
    }
    elseif (-not $bw.remove.oem -or $null -eq $bw.remove.oem.exact) {
        Fail 'appx-bloatware.json : remove.oem (OEM / constructeur) manquant'
    }
    else {
        $oemCount = @($bw.remove.oem.exact).Count
        Ok ("appx-bloatware.json ({0} remove + {1} oem, {2} protected exact)" -f @($bw.remove.exact).Count, $oemCount, @($bw.protected.exact).Count)
    }
}

$braveOpt = Join-Path $configs 'brave-optimize.json'
if (Test-Path -LiteralPath $braveOpt) {
    $bo = Get-Content -LiteralPath $braveOpt -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $bo.disable) {
        Fail 'brave-optimize.json : propriete disable manquante'
    }
    elseif (-not $bo.disable.BraveRewardsDisabled) {
        Fail 'brave-optimize.json : BraveRewardsDisabled manquant'
    }
    else {
        Ok 'brave-optimize.json policies presentes'
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
    if (-not $gpu.chipset) {
        Fail 'gpu.json : cle chipset manquante'
    }
    elseif (-not $gpu.chipset.intel -or -not $gpu.chipset.intel.wingetId) {
        Fail 'gpu.json : chipset.intel.wingetId manquant'
    }
    elseif (-not $gpu.chipset.amd -or -not $gpu.chipset.amd.supportPage) {
        Fail 'gpu.json : chipset.amd.supportPage manquant'
    }
    elseif (-not $gpu.chipset.amd.bySocket -or (@($gpu.chipset.amd.bySocket).Count -lt 1)) {
        Fail 'gpu.json : chipset.amd.bySocket vide'
    }
    else {
        $socketOk = $true
        foreach ($rule in @($gpu.chipset.amd.bySocket)) {
            if (-not $rule.match -or -not $rule.label) {
                Fail 'gpu.json : entree bySocket sans match/label'
                $socketOk = $false
                break
            }
        }
        if ($socketOk) {
            Ok 'gpu.json cles amd/nvidia/chipset presentes'
        }
    }
}

$watchPath = Join-Path $configs 'game-mode-watch.json'
if (Test-Path -LiteralPath $watchPath) {
    $w = Get-Content -LiteralPath $watchPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $w.pollIntervalSeconds -or $null -eq $w.cpuThresholdPercent) {
        Fail 'game-mode-watch.json : seuils agent maintenance manquants'
    }
    else {
        Ok 'game-mode-watch.json structure OK'
    }
}

$mcPath = Join-Path $configs 'maintenance-content.json'
$launcherPath = Join-Path $root 'launcher.ps1'
$corePath = Join-Path $root 'scripts/lib/Launcher-Core.ps1'
if ((Test-Path -LiteralPath $mcPath) -and (Test-Path -LiteralPath $launcherPath) -and (Test-Path -LiteralPath $corePath)) {
    $mc = Get-Content -LiteralPath $mcPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($null -eq $mc.epoch) {
        Fail 'maintenance-content.json : epoch manquant'
    }
    else {
        $le = ''
        $ce = ''
        $lr = Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8
        $cr = Get-Content -LiteralPath $corePath -Raw -Encoding UTF8
        if ($lr -match 'FreshWindowsLibEpoch\s*=\s*(\d+)') { $le = $Matches[1] }
        if ($cr -match 'FreshWindowsLibEpoch\s*=\s*(\d+)') { $ce = $Matches[1] }
        $me = [string]$mc.epoch
        if ($le -ne $ce -or $le -ne $me) {
            Fail ("maintenance-content epoch {0} != launcher {1} / core {2}" -f $me, $le, $ce)
        }
        else {
            Ok ("maintenance-content.json epoch {0} aligne launcher/core" -f $me)
        }
    }
}

Write-Host ""
if ($failed -gt 0) {
    Write-Host ("{0} echec(s)" -f $failed) -ForegroundColor Red
    exit 1
}
Write-Host "Tous les tests configs OK." -ForegroundColor Green
exit 0
