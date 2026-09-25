#Requires -Version 5.1
<#
  TTS Fresh Agent : edge-tts (defaut), Windows SAPI (secours), Piper (legacy).
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

function Find-FreshAgentPythonExe {
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python310\python.exe'),
            'python'
        )) {
        if ($c -eq 'python') {
            $cmd = Get-Command python -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
            continue
        }
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
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
        $voiceName = $null
        $enabled = @($synth.GetInstalledVoices() | Where-Object { $_.Enabled })
        $fr = @($enabled | Where-Object { $_.VoiceInfo.Culture -and $_.VoiceInfo.Culture.Name -like 'fr*' })
        $pool = if ($fr.Count -gt 0) { $fr } else { $enabled }
        $fem = @($pool | Where-Object { $_.VoiceInfo.Gender -eq [System.Speech.Synthesis.VoiceGender]::Female })
        $pick = if ($fem.Count -gt 0) { $fem[0] } elseif ($pool.Count -gt 0) { $pool[0] } else { $null }
        if ($pick) {
            $voiceName = [string]$pick.VoiceInfo.Name
            $synth.SelectVoice($voiceName)
        }
        if ($AiConfig -and $AiConfig.tts -and $AiConfig.tts.windows) {
            if ($null -ne $AiConfig.tts.windows.rate) {
                $synth.Rate = [int]$AiConfig.tts.windows.rate
            }
            if ($null -ne $AiConfig.tts.windows.volume) {
                $synth.Volume = [int]$AiConfig.tts.windows.volume
            }
        }
        $synth.Speak($Text)
        return $true
    }
    finally {
        try { $synth.Dispose() } catch { }
    }
}

function Invoke-FreshAgentEdgeTts {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        $AiConfig,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $py = Find-FreshAgentPythonExe
    if (-not $py) { return $false }

    $voice = 'fr-FR-DeniseNeural'
    $rate = '+0%'
    $volume = '+0%'
    if ($AiConfig -and $AiConfig.tts -and $AiConfig.tts.edge) {
        if ($AiConfig.tts.edge.voice) { $voice = [string]$AiConfig.tts.edge.voice }
        if ($AiConfig.tts.edge.rate) { $rate = [string]$AiConfig.tts.edge.rate }
        if ($AiConfig.tts.edge.volume) { $volume = [string]$AiConfig.tts.edge.volume }
    }

    $outDir = Join-Path $FreshAppData 'tts-cache'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $mp3 = Join-Path $outDir ('edge-{0}.mp3' -f ([guid]::NewGuid().ToString('N')))

    # Ensure edge-tts quietly (once per process)
    if (-not $script:FreshAgentEdgeTtsReady) {
        $check = & $py -c "import edge_tts" 2>&1
        if ($LASTEXITCODE -ne 0) {
            & $py -m pip install --user --quiet edge-tts 2>&1 | Out-Null
        }
        $script:FreshAgentEdgeTtsReady = $true
    }

    $code = @"
import asyncio, edge_tts, sys
async def main():
    communicate = edge_tts.Communicate(sys.argv[1], sys.argv[2], rate=sys.argv[3], volume=sys.argv[4])
    await communicate.save(sys.argv[5])
asyncio.run(main())
"@
    $pyFile = Join-Path $outDir 'edge_speak.py'
    Set-Content -LiteralPath $pyFile -Value $code -Encoding UTF8
    $p = Start-Process -FilePath $py -ArgumentList @($pyFile, $Text, $voice, $rate, $volume, $mp3) -Wait -PassThru -WindowStyle Hidden
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $mp3)) {
        return $false
    }
    try {
        Add-Type -AssemblyName presentationCore -ErrorAction SilentlyContinue
        $player = New-Object System.Windows.Media.MediaPlayer
        $uri = [uri]::new((Resolve-Path -LiteralPath $mp3).Path)
        $player.Open($uri)
        $player.Play()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt 120000) {
            Start-Sleep -Milliseconds 200
            if ($player.NaturalDuration.HasTimeSpan -and $player.Position -ge $player.NaturalDuration.TimeSpan) { break }
            if ($sw.ElapsedMilliseconds -gt 2000 -and $player.NaturalDuration.HasTimeSpan -eq $false) { break }
        }
        $player.Close()
        return $true
    }
    catch {
        # Fallback: start default associated player briefly
        try {
            Start-Process -FilePath $mp3 -WindowStyle Hidden | Out-Null
            Start-Sleep -Seconds 2
            return $true
        }
        catch { return $false }
    }
    finally {
        try { Remove-Item -LiteralPath $mp3 -Force -ErrorAction SilentlyContinue } catch { }
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
    if (-not (Get-Command Expand-FreshAgentPath -ErrorAction SilentlyContinue)) { return $false }
    $exe = Expand-FreshAgentPath -Path ([string]$piper.exe)
    $model = Expand-FreshAgentPath -Path ([string]$piper.model)
    if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $model)) {
        return $false
    }
    $outDir = Join-Path $FreshAppData 'tts-cache'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $wav = Join-Path $outDir ('out-{0}.wav' -f ([guid]::NewGuid().ToString('N')))

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
        return $true
    }
    catch { return $false }
    finally {
        try { Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function Invoke-FreshAgentSpeak {
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        $AiConfig,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $spoken = $Text
    if ($spoken.Length -gt 320) {
        $spoken = $spoken.Substring(0, 317) + '...'
    }
    $provider = Get-FreshAgentTtsProvider -AiConfig $AiConfig
    switch ($provider) {
        'edge' {
            if (Invoke-FreshAgentEdgeTts -Text $spoken -AiConfig $AiConfig -FreshAppData $FreshAppData) { return $true }
            return (Invoke-FreshAgentWindowsTts -Text $spoken -AiConfig $AiConfig)
        }
        'windows' {
            return (Invoke-FreshAgentWindowsTts -Text $spoken -AiConfig $AiConfig)
        }
        'piper' {
            if (Invoke-FreshAgentPiperTts -Text $spoken -AiConfig $AiConfig -FreshAppData $FreshAppData) { return $true }
            return (Invoke-FreshAgentWindowsTts -Text $spoken -AiConfig $AiConfig)
        }
        default { return $false }
    }
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
