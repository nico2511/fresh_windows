#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-VoiceRouter.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-Health.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-Confirm.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-ActionLog.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-WindowsActions.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-Optimize.ps1')

$tmp = Join-Path $env:TEMP ('vr-' + [guid]::NewGuid().ToString('N'))
$rd = Join-Path $tmp 'configs\skills\router'
New-Item -ItemType Directory -Path $rd -Force | Out-Null
Copy-Item (Join-Path $root 'configs\skills\router\fr-pc.json') (Join-Path $rd 'fr-pc.json')
$appsDir = Join-Path $tmp 'configs'
New-Item -ItemType Directory -Path $appsDir -Force | Out-Null
Copy-Item (Join-Path $root 'configs\skills-apps.json') (Join-Path $appsDir 'skills-apps.json')

# Build accented phrase via codepoints (Windows PowerShell 5.1 may misread UTF-8 .ps1)
$etat = ([string][char]0x00C9) + 'tat du syst' + ([string][char]0x00E8) + 'me.'
$n = ConvertTo-FreshAgentVoiceNormalized -Text $etat
if ($n -ne 'etat du systeme') { throw "norm failed: [$n]" }

$m = Resolve-FreshAgentVoiceRouterMatch -Transcript $etat -FreshAppData $tmp
if (-not $m.matched -or $m.skillId -ne 'check_system_health') { throw "health fail: $($m.skillId)" }

$m2 = Resolve-FreshAgentVoiceRouterMatch -Transcript 'Lance Steam' -FreshAppData $tmp
if (-not $m2.matched -or $m2.skillId -ne 'launch_app') { throw "steam fail: $($m2.skillId)" }
$m3 = Resolve-FreshAgentVoiceRouterMatch -Transcript 'lancer steam' -FreshAppData $tmp
if (-not $m3.matched -or $m3.skillId -ne 'launch_app') { throw "lancer steam fail: $($m3.skillId)" }

# Compact key: grokbot == "Grok Bot" (sans alias hardcode)
$k1 = ConvertTo-FreshAgentAppCompactKey -Text 'grokbot'
$k2 = ConvertTo-FreshAgentAppCompactKey -Text 'Grok Bot'
if ($k1 -ne $k2) { throw "compact key fail: $k1 vs $k2" }

# Compact + fuzzy: grokbot resolu si present au Start Menu (skip si absent sur CI)
try {
    $gb = Resolve-FreshAgentSpokenAppName -Name 'grokbot' -FreshAppData $tmp
    if ($gb -and $gb -ne 'grokbot' -and $gb -notmatch '(?i)grok') {
        throw "fuzzy grokbot unexpected: $gb"
    }
}
catch { if ($_.Exception.Message -match 'fuzzy grokbot') { throw } }
# skills-apps: steam exact
$st = Resolve-FreshAgentSpokenAppName -Name 'steam' -FreshAppData $tmp
if ($st -notmatch '(?i)steam') { throw "steam resolve fail: $st" }

$r = Stop-FreshAgentProcessVerified -ProcessId $PID -ProcessName 'DefinitelyNot'
if ($r.ok) { throw 'kill should fail' }

if ((Resolve-FreshAgentConfirmUtterance -Transcript 'oui') -ne 'confirm') { throw 'confirm' }
if ((Resolve-FreshAgentConfirmUtterance -Transcript 'annule') -ne 'cancel') { throw 'cancel' }

Add-FreshAgentActionLogEntry -Action 'test' -Message 'ok' -FreshAppData $tmp
$log = @(Get-FreshAgentActionLogRecent -Count 1 -FreshAppData $tmp)
if ($log.Count -lt 1) { throw 'action log empty' }

# Ensure BackgroundWorker param accepts BuildRagIndex (parse only)
$bg = Get-Content (Join-Path $root 'scripts\ai\FreshAgent-BackgroundWorker.ps1') -Raw
if ($bg -notmatch "BuildRagIndex") { throw 'BackgroundWorker missing BuildRagIndex' }

Write-Host 'OK Smoke-VoiceHealth'
