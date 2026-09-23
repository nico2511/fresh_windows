#Requires -Version 5.1
<#
  STT via API Windows (System.Speech) — Phase 3 push-to-talk menu agent.
#>

function Test-WindowsSpeechRecognitionAvailable {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $engines = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
        return ($engines.Count -gt 0)
    }
    catch { }
    return $false
}

function Get-WindowsSttStatusMessage {
    $cfg = $null
    if (Get-Command Get-FreshAgentAiConfig -ErrorAction SilentlyContinue) {
        try {
            $cfg = Get-FreshAgentAiConfig
        }
        catch { }
    }
    if ($cfg -and $cfg.stt -and $cfg.stt.provider -eq 'cyberScribe') {
        return 'STT : CyberScribe (non gere par cet agent — utilise mode Windows).'
    }
    if (-not (Test-WindowsSpeechRecognitionAvailable)) {
        return 'STT Windows indisponible (micro / pack langue).'
    }
    $culture = Get-WindowsSttCulture -AiConfig $cfg
    return "STT Windows pret ($culture)."
}

function Test-FreshAgentWindowsSttEnabled {
    param($AiConfig)
    if (-not $AiConfig -or -not $AiConfig.stt) { return $false }
    if ([string]$AiConfig.stt.provider -ne 'windows') { return $false }
    return (Test-WindowsSpeechRecognitionAvailable)
}

function Get-WindowsSttCulture {
    param($AiConfig)
    $name = 'fr-FR'
    if ($AiConfig -and $AiConfig.stt -and $AiConfig.stt.culture) {
        $name = [string]$AiConfig.stt.culture
    }
    try {
        return [System.Globalization.CultureInfo]::GetCultureInfo($name)
    }
    catch {
        return [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    }
}

function Get-WindowsSttListenSeconds {
    param($AiConfig)
    $sec = 20
    if ($AiConfig -and $AiConfig.stt -and $null -ne $AiConfig.stt.listenSeconds) {
        $sec = [int]$AiConfig.stt.listenSeconds
    }
    if ($sec -lt 5) { $sec = 5 }
    if ($sec -gt 60) { $sec = 60 }
    return $sec
}

function Get-WindowsSttMinConfidence {
    param($AiConfig)
    $c = 0.42
    if ($AiConfig -and $AiConfig.stt -and $null -ne $AiConfig.stt.minConfidence) {
        $c = [double]$AiConfig.stt.minConfidence
    }
    if ($c -lt 0.1) { $c = 0.1 }
    if ($c -gt 0.95) { $c = 0.95 }
    return $c
}

function New-WindowsSpeechRecognitionEngine {
    param($AiConfig)
    Add-Type -AssemblyName System.Speech -ErrorAction Stop
    $culture = Get-WindowsSttCulture -AiConfig $AiConfig
    $recognizers = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
    $picked = $null
    foreach ($r in $recognizers) {
        if ($r.Culture.Name -eq $culture.Name) {
            $picked = $r
            break
        }
    }
    if (-not $picked -and $recognizers.Count -gt 0) {
        $picked = $recognizers[0]
    }
    if (-not $picked) {
        throw 'Aucun moteur de reconnaissance installe.'
    }
    $engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine($picked)
    $engine.SetInputToDefaultAudioDevice()
    $grammar = New-Object System.Speech.Recognition.DictationGrammar
    $engine.LoadGrammar($grammar)
    return $engine
}

function Invoke-WindowsSttListenInteractive {
    param(
        $AiConfig
    )
    if (-not (Test-FreshAgentWindowsSttEnabled -AiConfig $AiConfig)) {
        throw 'STT Windows indisponible ou provider != windows.'
    }

    $timeoutSec = Get-WindowsSttListenSeconds -AiConfig $AiConfig
    $minConfidence = Get-WindowsSttMinConfidence -AiConfig $AiConfig
    $engine = $null

    $script:SttListenResult = $null
    $script:SttListenDone = $false

    try {
        $engine = New-WindowsSpeechRecognitionEngine -AiConfig $AiConfig

        $engine.Add_SpeechRecognized({
                param($sender, $e)
                if ($null -eq $e -or $null -eq $e.Result) { return }
                if ($e.Result.Rejected) { return }
                if ($e.Result.Confidence -lt $minConfidence) { return }
                $script:SttListenResult = $e.Result.Text
                $script:SttListenDone = $true
            })

        $engine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Single)

        $deadline = (Get-Date).AddSeconds($timeoutSec)
        while (-not $script:SttListenDone -and (Get-Date) -lt $deadline) {
            if (Get-Command -Name 'Application' -ErrorAction SilentlyContinue) {
                [System.Windows.Forms.Application]::DoEvents()
            }
            Start-Sleep -Milliseconds 60
        }

        try { $engine.RecognizeAsyncStop() } catch { }
        return $script:SttListenResult
    }
    finally {
        if ($engine) {
            try { $engine.Dispose() } catch { }
        }
    }
}

function Get-FreshAgentVoiceDirectSkill {
    param(
        [Parameter(Mandatory)]
        [string]$Transcript
    )
    $t = $Transcript.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }

    if ($t -match 'fin (de )?session|fin session jeu|arrete session') {
        return @{ SkillId = 'end_game_session'; Parameters = @{} }
    }
    if ($t -match 'session jeu|mode jeu|lance(r)? session') {
        return @{ SkillId = 'game_session'; Parameters = @{} }
    }
    if ($t -match 'etat systeme|état système|sante systeme|cpu|ram') {
        return @{ SkillId = 'check_system_health'; Parameters = @{} }
    }
    if ($t -match 'youtube') {
        $q = $Transcript
        if ($t -match 'youtube\s+(.+)') { $q = $Matches[1] }
        elseif ($t -match 'sur youtube\s+(.+)') { $q = $Matches[1] }
        elseif ($t -match 'met(s)?(.+)sur youtube') { $q = $Matches[2] }
        $q = $q.Trim()
        if ($q.Length -gt 2) {
            return @{ SkillId = 'youtube_search'; Parameters = @{ query = $q } }
        }
    }
    return $null
}

function Invoke-FreshAgentProcessVoiceTranscript {
    param(
        [Parameter(Mandatory)]
        [string]$Transcript,
        $AiConfig,
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }),
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )

    $route = 'auto'
    if ($AiConfig -and $AiConfig.stt -and $AiConfig.stt.route) {
        $route = [string]$AiConfig.stt.route
    }

    $direct = $null
    if ($route -eq 'auto' -or $route -eq 'skills') {
        $direct = Get-FreshAgentVoiceDirectSkill -Transcript $Transcript
    }

    if ($direct -and ($route -eq 'skills' -or -not $AiConfig.enabled)) {
        return Invoke-FreshAgentSkill -SkillId $direct.SkillId -Parameters $direct.Parameters -RepoRef $RepoRef -FreshAppData $FreshAppData
    }

    if ($AiConfig -and $AiConfig.enabled -and ($route -eq 'ai' -or $route -eq 'auto')) {
        if (Get-Command Ensure-FreshAgentAiBridgeLoaded -ErrorAction SilentlyContinue) {
            Ensure-FreshAgentAiBridgeLoaded -FreshAppData $FreshAppData | Out-Null
        }
        if (Get-Command Invoke-FreshAgentAiTurn -ErrorAction SilentlyContinue) {
            return Invoke-FreshAgentAiTurn -UserPrompt $Transcript -AiConfig $AiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
        }
    }

    if ($direct) {
        return Invoke-FreshAgentSkill -SkillId $direct.SkillId -Parameters $direct.Parameters -RepoRef $RepoRef -FreshAppData $FreshAppData
    }

    return @{
        ok      = $false
        message = 'Active l IA (menu) ou reformule (session jeu, etat systeme, youtube ...).'
    }
}
