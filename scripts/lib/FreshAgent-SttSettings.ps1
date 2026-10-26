#Requires -Version 5.1
<#
  Parametres STT partages (host detache + agent tray).
#>

function Get-FreshAgentSttListenMode {
    param($AiConfig = $null)
    if (-not $AiConfig -or -not $AiConfig.stt) { return 'pushToTalk' }
    $mode = [string]$AiConfig.stt.listenMode
    if ($mode -eq 'alwaysOn') { return 'alwaysOn' }
    if ($mode -eq 'pushToTalk') { return 'pushToTalk' }
    if ($null -ne $AiConfig.stt.pushToTalk) {
        if ([bool]$AiConfig.stt.pushToTalk) { return 'pushToTalk' }
        return 'alwaysOn'
    }
    return 'pushToTalk'
}

function Test-FreshAgentSttPushToTalkFromConfig {
    param($AiConfig = $null)
    return (Get-FreshAgentSttListenMode -AiConfig $AiConfig) -eq 'pushToTalk'
}

function Expand-FreshAgentModelsPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if (Get-Command Expand-FreshAgentPath -ErrorAction SilentlyContinue) {
        return Expand-FreshAgentPath -Path $Path
    }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Write-FreshAgentModelsDirLegacyLogOnce {
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [Parameter(Mandatory)][string]$Message,
        [scriptblock]$OnLegacyPath = $null
    )
    $flag = Join-Path $FreshAppData 'fa-models-legacy-notified.txt'
    if (Test-Path -LiteralPath $flag) { return }
    try {
        Set-Content -LiteralPath $flag -Value (Get-Date).ToString('o') -Encoding UTF8 -NoNewline
    }
    catch { return }
    if ($OnLegacyPath) {
        try { & $OnLegacyPath $Message } catch { }
    }
}

function Get-FreshAgentModelsDirFromUserConfigs {
    param([Parameter(Mandatory)][string]$FreshAppData)
    foreach ($path in @(
            (Join-Path $FreshAppData 'agent-ai.user.json'),
            (Join-Path $FreshAppData 'watch-agent-user.json')
        )) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $u = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $candidates = @()
            if ($u.freshModelsDir) { $candidates += [string]$u.freshModelsDir }
            if ($u.modelsDir) { $candidates += [string]$u.modelsDir }
            if ($u.stt -and $u.stt.modelsDir) { $candidates += [string]$u.stt.modelsDir }
            foreach ($c in $candidates) {
                if (-not [string]::IsNullOrWhiteSpace($c)) {
                    return Expand-FreshAgentModelsPath -Path $c.Trim()
                }
            }
        }
        catch { }
    }
    return $null
}

function Resolve-FreshAgentModelsDir {
    <#
      a) config user (watch-agent-user.json, agent-ai.user.json : freshModelsDir, modelsDir, stt.modelsDir)
      b) env FRESH_MODELS_DIR
      c) defaut %LOCALAPPDATA%\FreshWindows\models
      Retrocompat (aucun reglage a/b) : D:\models\cyberscribe_models si present (journalise une fois).
    #>
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [scriptblock]$OnLegacyPath = $null
    )
    $fromUser = Get-FreshAgentModelsDirFromUserConfigs -FreshAppData $FreshAppData
    if (-not [string]::IsNullOrWhiteSpace($fromUser)) {
        return $fromUser
    }
    if ($env:FRESH_MODELS_DIR -and -not [string]::IsNullOrWhiteSpace($env:FRESH_MODELS_DIR)) {
        return Expand-FreshAgentModelsPath -Path $env:FRESH_MODELS_DIR.Trim()
    }
    $legacy = 'D:\models\cyberscribe_models'
    if (Test-Path -LiteralPath $legacy) {
        $msg = "modelsDir legacy D:\models\cyberscribe_models (definir freshModelsDir, FRESH_MODELS_DIR ou %LOCALAPPDATA%\FreshWindows\models)"
        Write-FreshAgentModelsDirLegacyLogOnce -FreshAppData $FreshAppData -Message $msg -OnLegacyPath $OnLegacyPath
        return $legacy
    }
    $localApp = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($localApp) -and $env:USERPROFILE) {
        $localApp = Join-Path $env:USERPROFILE 'AppData\Local'
    }
    if ([string]::IsNullOrWhiteSpace($localApp)) {
        $localApp = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    }
    return (Join-Path $localApp 'FreshWindows\models')
}

function Resolve-FreshAgentSttModelSize {
    param(
        [string]$Requested = 'small',
        [string]$ModelsDir = ''
    )
    if ([string]::IsNullOrWhiteSpace($Requested)) { $Requested = 'small' }
    $Requested = $Requested.Trim().ToLowerInvariant()
    if ($Requested -eq 'base') { $Requested = 'small' }

    $rankOrder = @('large-v3', 'large-v2', 'large', 'medium', 'small', 'base', 'tiny')
    $rank = @{}
    for ($i = 0; $i -lt $rankOrder.Count; $i++) { $rank[$rankOrder[$i]] = $i }

    if ([string]::IsNullOrWhiteSpace($ModelsDir) -or -not (Test-Path -LiteralPath $ModelsDir)) {
        return $Requested
    }

    $found = New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($item in Get-ChildItem -LiteralPath $ModelsDir -ErrorAction SilentlyContinue) {
            $name = $item.Name.ToLowerInvariant()
            foreach ($tag in $rankOrder) {
                if ($name -match $tag -and ($found -notcontains $tag)) {
                    $found.Add($tag)
                }
            }
        }
    }
    catch { }

    if ($found.Count -lt 1) { return $Requested }

    $best = $null
    foreach ($tag in $rankOrder) {
        if ($found -contains $tag) { $best = $tag; break }
    }
    if (-not $best) { return $Requested }

    if ($rank.ContainsKey($Requested) -and $rank.ContainsKey($best)) {
        if ($rank[$best] -ge $rank[$Requested]) { return $best }
    }
    return $Requested
}

function Get-FreshAgentSttHostTiming {
    param(
        $Stt,
        [bool]$PushToTalk
    )
    $maxRec = 8
    $silenceMs = 1000
    $minRec = 450
    if ($Stt) {
        if ($null -ne $Stt.maxRecordSeconds) { $maxRec = [int]$Stt.maxRecordSeconds }
        elseif ($null -ne $Stt.listenSeconds) { $maxRec = [int]$Stt.listenSeconds }
        if ($null -ne $Stt.silenceMs) { $silenceMs = [int]$Stt.silenceMs }
        if ($null -ne $Stt.minRecordMs) { $minRec = [int]$Stt.minRecordMs }
    }
    if ($PushToTalk) {
        if ($maxRec -lt 30) { $maxRec = 30 }
        if ($silenceMs -lt 60000) { $silenceMs = 60000 }
        if ($minRec -lt 350) { $minRec = 350 }
    }
    else {
        if ($silenceMs -gt 5000 -or $silenceMs -lt 250) { $silenceMs = 1000 }
        if ($maxRec -gt 30) { $maxRec = 12 }
        if ($maxRec -lt 4) { $maxRec = 6 }
        if ($minRec -lt 400) { $minRec = 400 }
    }
    return @{
        maxRecordSeconds = $maxRec
        silenceMs        = $silenceMs
        minRecordMs      = $minRec
    }
}

function Test-FreshAgentVoiceHostTranscriptUseful {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $t = $Text.Trim()
    if ($t.Length -lt 3) { return $false }
    $letters = ([regex]::Matches($t, '\p{L}')).Count
    if ($letters -lt 3) { return $false }
    $norm = $t.ToLowerInvariant() -replace '[^\p{L}\p{N}\s]', '' -replace '\s+', ' '
    $norm = $norm.Trim()
    $junkExact = @(
        'sous-titres', 'subtitl', 'merci', 'thanks', 'music', 'musique',
        'applaudissements', 'silence', 'you', 'the end', 'fin',
        'cest ca', 'c est ca', 'ah', 'euh', 'hmm',
        'stimme', 'stimme stimme', 'xen', 'lors', 'loss', 'l oss',
        'scribe', 'scribe scribe', 'cyber scribe', 'cyberscribe'
    )
    foreach ($j in $junkExact) {
        if ($norm -eq $j) { return $false }
    }
    $parts = @($norm -split '\s+' | Where-Object { $_ })
    if ($parts.Count -ge 2) {
        $uniq = @($parts | Select-Object -Unique)
        if ($uniq.Count -eq 1 -and $parts[0].Length -le 10) { return $false }
    }
    if ($parts.Count -eq 1 -and $parts[0].Length -le 4 -and $parts[0] -notmatch '^(oui|non|ok|go)$') {
        return $false
    }
    return $true
}

function New-FreshAgentPttMachineState {
    return @{
        KeyWasDown       = $false
        Holding          = $false
        RequireRelease   = $false
        PendingStart     = $false
    }
}

function Update-FreshAgentPttMachine {
    <#
      Machine a etats PTT (edge-triggered). Retourne @{ State; Actions = @('start','stop') }.
    #>
    param(
        [hashtable]$State,
        [bool]$KeyDown,
        [bool]$Recording,
        [bool]$Transcribing
    )
    if (-not $State) { $State = New-FreshAgentPttMachineState }
    $actions = @()
    $wasDown = [bool]$State.KeyWasDown
    $State.KeyWasDown = $KeyDown

    if ($Transcribing) {
        if (-not $KeyDown) {
            $State.RequireRelease = $false
            $State.Holding = $false
            $State.PendingStart = $false
        }
        return @{ State = $State; Actions = $actions }
    }

    if ($State.RequireRelease) {
        if (-not $KeyDown) { $State.RequireRelease = $false }
        return @{ State = $State; Actions = $actions }
    }

    if ($KeyDown -and -not $wasDown) {
        if (-not $Recording -and -not $State.PendingStart) {
            $State.Holding = $true
            $State.PendingStart = $true
            $actions += 'start'
        }
    }
    elseif (-not $KeyDown -and $wasDown) {
        $State.Holding = $false
        $State.PendingStart = $false
        if ($Recording) { $actions += 'stop' }
    }
    elseif ($KeyDown -and $wasDown -and $Recording) {
        $State.PendingStart = $false
    }
    elseif (-not $KeyDown) {
        $State.PendingStart = $false
    }

    return @{ State = $State; Actions = $actions }
}

function Sync-FreshAgentPttMachineAfterRecording {
    param(
        [hashtable]$State,
        [bool]$KeyDown,
        [bool]$Recording
    )
    if (-not $State) { $State = New-FreshAgentPttMachineState }
    if (-not $Recording -and $State.Holding -and $KeyDown) {
        $State.RequireRelease = $true
        $State.Holding = $false
        $State.PendingStart = $false
    }
    return $State
}
