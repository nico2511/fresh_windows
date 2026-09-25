#Requires -Version 5.1
<#
  STT via API Windows (System.Speech) — Phase 3 push-to-talk menu agent.
#>

function Test-WindowsSpeechRecognitionAvailable {
    # Ne cacher que les succes: un echec transitoire au boot ne doit pas griser le STT pour toujours.
    if ($script:FreshAgentSpeechAvailCache -eq $true) {
        return $true
    }
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $engines = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
        if ($engines -and $engines.Count -gt 0) {
            $script:FreshAgentSpeechAvailCache = $true
            return $true
        }
    }
    catch { }
    return $false
}

function Get-WindowsSttStatusMessage {
    param(
        [string]$FreshAppData,
        [string]$RepoRef
    )
    $cfg = $null
    if (Get-Command Get-FreshAgentAiConfig -ErrorAction SilentlyContinue) {
        try {
            $p = @{ PreferLocal = $true }
            if ($FreshAppData) { $p.FreshAppData = $FreshAppData }
            if ($RepoRef) { $p.RepoRef = $RepoRef }
            $cfg = Get-FreshAgentAiConfig @p
        }
        catch { }
    }
    $provider = 'windows'
    if ($cfg -and $cfg.stt -and $cfg.stt.provider) {
        $provider = [string]$cfg.stt.provider
    }
    if ($provider -eq 'cyberScribe') {
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
    # Provider absent = windows (defaut agent). Seul cyberScribe desactive ce chemin.
    $provider = 'windows'
    if ($AiConfig -and $AiConfig.stt -and $AiConfig.stt.provider) {
        $provider = [string]$AiConfig.stt.provider
    }
    if ($provider -ne 'windows') { return $false }
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

    $global:FreshAgentSttResult = $null
    $global:FreshAgentSttDone = $false
    $global:FreshAgentSttMinConfidence = $minConfidence

    try {
        $engine = New-WindowsSpeechRecognitionEngine -AiConfig $AiConfig

        # Handler WinForms: pas de variable locale, uniquement $global: (sinon le texte est perdu).
        $engine.Add_SpeechRecognized({
                param($sender, $e)
                try {
                    if ($null -eq $e -or $null -eq $e.Result) { return }
                    $text = [string]$e.Result.Text
                    $conf = [double]$e.Result.Confidence
                    $min = 0.25
                    if ($null -ne $global:FreshAgentSttMinConfidence) { $min = [double]$global:FreshAgentSttMinConfidence }
                    $global:FreshAgentSttLastNote = ("conf={0:N2} text={1}" -f $conf, $text)
                    if ($e.Result.Rejected -or $conf -lt $min -or [string]::IsNullOrWhiteSpace($text)) { return }
                    $global:FreshAgentSttResult = $text
                    $global:FreshAgentSttDone = $true
                    $global:FreshAgentSttPending = $text
                }
                catch {
                    $global:FreshAgentSttLastNote = $_.Exception.Message
                }
            })

        $engine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Single)

        $deadline = (Get-Date).AddSeconds($timeoutSec)
        while (-not $global:FreshAgentSttDone -and (Get-Date) -lt $deadline) {
            if (Get-Command -Name 'Application' -ErrorAction SilentlyContinue) {
                [System.Windows.Forms.Application]::DoEvents()
            }
            Start-Sleep -Milliseconds 60
        }

        try { $engine.RecognizeAsyncStop() } catch { }
        return $global:FreshAgentSttResult
    }
    finally {
        if ($engine) {
            try { $engine.Dispose() } catch { }
        }
    }
}

function Start-WindowsSttAlwaysOn {
    param($AiConfig)
    if ($global:FreshAgentSttEngine) { return $true }
    $global:FreshAgentSttMinConfidence = Get-WindowsSttMinConfidence -AiConfig $AiConfig
    if ($global:FreshAgentSttMinConfidence -gt 0.35) { $global:FreshAgentSttMinConfidence = 0.35 }
    $global:FreshAgentSttPaused = $false
    $global:FreshAgentSttPending = $null
    $engine = New-WindowsSpeechRecognitionEngine -AiConfig $AiConfig
    $engine.Add_SpeechRecognized({
            param($sender, $e)
            try {
                if ($global:FreshAgentSttPaused) { return }
                if ($null -eq $e -or $null -eq $e.Result) { return }
                $text = [string]$e.Result.Text
                $conf = [double]$e.Result.Confidence
                $min = 0.35
                if ($null -ne $global:FreshAgentSttMinConfidence) { $min = [double]$global:FreshAgentSttMinConfidence }
                $global:FreshAgentSttLastNote = ("conf={0:N2} text={1}" -f $conf, $text)
                if ($e.Result.Rejected -or $conf -lt $min -or [string]::IsNullOrWhiteSpace($text)) { return }
                if ($global:FreshAgentSttPending) { return }
                $global:FreshAgentSttPending = $text
            }
            catch {
                $global:FreshAgentSttLastNote = $_.Exception.Message
            }
        })
    $engine.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)
    $global:FreshAgentSttEngine = $engine
    return $true
}

function Stop-WindowsSttAlwaysOn {
    $engine = $global:FreshAgentSttEngine
    $global:FreshAgentSttEngine = $null
    $global:FreshAgentSttPending = $null
    if ($engine) {
        try { $engine.RecognizeAsyncCancel() } catch { }
        try { $engine.Dispose() } catch { }
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
