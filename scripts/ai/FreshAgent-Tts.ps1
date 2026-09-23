#Requires -Version 5.1
<#
  TTS Fresh Agent : Windows SAPI (defaut) ou Piper (opt-in).
#>

function Get-FreshAgentTtsProvider {
    param($AiConfig)
    if (-not $AiConfig -or -not $AiConfig.tts) { return 'off' }
    $p = [string]$AiConfig.tts.provider
    if ([string]::IsNullOrWhiteSpace($p)) { return 'off' }
    return $p.Trim().ToLowerInvariant()
}

function Test-FreshAgentTtsEnabled {
    param($AiConfig)
    return (Get-FreshAgentTtsProvider -AiConfig $AiConfig) -ne 'off'
}

function Test-FreshAgentShouldSpeakSkillResults {
    param($AiConfig)
    if (-not (Test-FreshAgentTtsEnabled -AiConfig $AiConfig)) { return $false }
    if ($null -eq $AiConfig.tts.speakSkillResults) { return $true }
    return [bool]$AiConfig.tts.speakSkillResults
}

function Invoke-FreshAgentWindowsTts {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        $AiConfig
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    Add-Type -AssemblyName System.Speech -ErrorAction Stop
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        $culture = 'fr-FR'
        if ($AiConfig -and $AiConfig.tts -and $AiConfig.tts.windows -and $AiConfig.tts.windows.culture) {
            $culture = [string]$AiConfig.tts.windows.culture
        }
        try {
            $synth.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Neutral, `
                [System.Speech.Synthesis.VoiceAge]::Adult, 0, `
                [System.Globalization.CultureInfo]::GetCultureInfo($culture))
        }
        catch { }
        if ($AiConfig -and $AiConfig.tts -and $AiConfig.tts.windows) {
            if ($null -ne $AiConfig.tts.windows.rate) {
                $synth.Rate = [int]$AiConfig.tts.windows.rate
            }
            if ($null -ne $AiConfig.tts.windows.volume) {
                $synth.Volume = [int]$AiConfig.tts.windows.volume
            }
        }
        $synth.SpeakAsync($Text) | Out-Null
        return $true
    }
    finally {
        $synth.Dispose()
    }
}

function Invoke-FreshAgentPiperTts {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        $AiConfig,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $piper = $AiConfig.tts.piper
    if (-not $piper) { return $false }
    $exe = Expand-FreshAgentPath -Path ([string]$piper.exe)
    $model = Expand-FreshAgentPath -Path ([string]$piper.model)
    if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $model)) {
        return $false
    }
    $outDir = Join-Path $FreshAppData 'tts-cache'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $wav = Join-Path $outDir ('out-{0}.wav' -f ([guid]::NewGuid().ToString('N')))
    $inFile = Join-Path $outDir 'piper-in.txt'
    Set-Content -LiteralPath $inFile -Value $Text -Encoding UTF8

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "--model `"$model`" --output_file `"$wav`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($Text)
    $p.StandardInput.Close()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $wav)) {
        return $false
    }
    try {
        $player = New-Object System.Media.SoundPlayer($wav)
        $player.PlaySync()
    }
    catch { return $false }
    finally {
        try { Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue } catch { }
    }
    return $true
}

function Invoke-FreshAgentSpeak {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        $AiConfig,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $provider = Get-FreshAgentTtsProvider -AiConfig $AiConfig
    if ($provider -eq 'off') { return $false }

    $spoken = $Text
    if ($spoken.Length -gt 320) {
        $spoken = $spoken.Substring(0, 317) + '...'
    }

    if ($provider -eq 'windows') {
        return (Invoke-FreshAgentWindowsTts -Text $spoken -AiConfig $AiConfig)
    }
    if ($provider -eq 'piper') {
        $ok = Invoke-FreshAgentPiperTts -Text $spoken -AiConfig $AiConfig -FreshAppData $FreshAppData
        if ($ok) { return $true }
        return (Invoke-FreshAgentWindowsTts -Text $spoken -AiConfig $AiConfig)
    }
    return $false
}

function Invoke-FreshAgentSpeakSkillResult {
    param(
        $Result,
        $AiConfig,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    if (-not (Test-FreshAgentShouldSpeakSkillResults -AiConfig $AiConfig)) { return }
    if (-not $Result -or -not $Result.message) { return }
    Invoke-FreshAgentSpeak -Text ([string]$Result.message) -AiConfig $AiConfig -FreshAppData $FreshAppData | Out-Null
}
