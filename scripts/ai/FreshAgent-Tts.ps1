#Requires -Version 5.1
<#
  TTS Fresh Agent : edge-tts (defaut), repli Windows SAPI si edge echoue.
  Piper / windows explicites sinon.
#>

function Write-FreshAgentTtsLog {
    param([string]$Message, [string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    try {
        $log = Join-Path $FreshAppData 'tts.log'
        Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    catch { }
}

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
    $txt = Join-Path $outDir ('edge-{0}.txt' -f ([guid]::NewGuid().ToString('N')))
    Set-Content -LiteralPath $txt -Value $Text -Encoding UTF8

    # Ensure edge-tts quietly (once per process)
    if (-not $script:FreshAgentEdgeTtsReady) {
        $check = & $py -c "import edge_tts" 2>&1
        if ($LASTEXITCODE -ne 0) {
            & $py -m pip install --user --quiet edge-tts 2>&1 | Out-Null
            $recheck = & $py -c "import edge_tts" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-FreshAgentTtsLog -Message 'edge_tts import failed' -FreshAppData $FreshAppData
                return $false
            }
        }
        $script:FreshAgentEdgeTtsReady = $true
    }

    $code = @"
import asyncio, edge_tts, sys
async def main():
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        text = f.read()
    communicate = edge_tts.Communicate(text, sys.argv[2], rate=sys.argv[3], volume=sys.argv[4])
    await communicate.save(sys.argv[5])
asyncio.run(main())
"@
    $pyFile = Join-Path $outDir 'edge_speak.py'
    Set-Content -LiteralPath $pyFile -Value $code -Encoding UTF8
    $errFile = Join-Path $outDir ('edge-err-{0}.txt' -f ([guid]::NewGuid().ToString('N')))
    $p = Start-Process -FilePath $py -ArgumentList @($pyFile, $txt, $voice, $rate, $volume, $mp3) `
        -Wait -PassThru -WindowStyle Hidden -RedirectStandardError $errFile
    try { Remove-Item -LiteralPath $txt -Force -ErrorAction SilentlyContinue } catch { }
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $mp3)) {
        $errSnippet = ''
        if (Test-Path -LiteralPath $errFile) {
            try {
                $errSnippet = ((Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ').Trim()
                if ($errSnippet.Length -gt 360) { $errSnippet = $errSnippet.Substring(0, 357) + '...' }
            }
            catch { }
        }
        Write-FreshAgentTtsLog -Message ("edge synthesize failed exit=$($p.ExitCode) stderr=$errSnippet") -FreshAppData $FreshAppData
        try { Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue } catch { }
        return $false
    }
    try { Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue } catch { }
    try {
        Add-Type -AssemblyName presentationCore -ErrorAction Stop
        $player = New-Object System.Windows.Media.MediaPlayer
        $full = (Resolve-Path -LiteralPath $mp3).Path
        $uri = [Uri]::new(('file:///' + ($full -replace '\\', '/')))
        $player.Open($uri)
        $player.Play()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $ready = $false
        while ($sw.ElapsedMilliseconds -lt 120000) {
            Start-Sleep -Milliseconds 150
            if ($player.NaturalDuration.HasTimeSpan) {
                $ready = $true
                if ($player.Position -ge $player.NaturalDuration.TimeSpan) { break }
            }
            elseif ($sw.ElapsedMilliseconds -gt 4000 -and -not $ready) {
                break
            }
        }
        $player.Stop()
        $player.Close()
        return $ready
    }
    catch {
        Write-FreshAgentTtsLog -Message ("edge play failed: $($_.Exception.Message)") -FreshAppData $FreshAppData
        return $false
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
            $ok = [bool](Invoke-FreshAgentEdgeTts -Text $spoken -AiConfig $AiConfig -FreshAppData $FreshAppData)
            if ($ok) { return $true }
            Write-FreshAgentTtsLog -Message 'edge failed -> windows SAPI fallback' -FreshAppData $FreshAppData
            return [bool](Invoke-FreshAgentWindowsTts -Text $spoken -AiConfig $AiConfig)
        }
        'windows' {
            return [bool](Invoke-FreshAgentWindowsTts -Text $spoken -AiConfig $AiConfig)
        }
        'piper' {
            return [bool](Invoke-FreshAgentPiperTts -Text $spoken -AiConfig $AiConfig -FreshAppData $FreshAppData)
        }
        default { return $false }
    }
}

function ConvertTo-FreshAgentSpokenSkillLine {
    <#
      Transforme un message skill technique en phrase orale FR.
      Preferer Result.spoken quand le handler en fournit une.
    #>
    param(
        $Result,
        [string]$Message = ''
    )
    if ($Result -and $Result.spoken -and -not [string]::IsNullOrWhiteSpace([string]$Result.spoken)) {
        return ([string]$Result.spoken).Trim()
    }
    $msg = if ($Message) { $Message.Trim() } elseif ($Result -and $Result.message) { ([string]$Result.message).Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($msg)) { return '' }

    # Ne pas lire un dump pipe a voix haute
    if ($msg -match '\|') {
        return 'Voila le resume systeme, regarde le bandeau pour le detail.'
    }

    if ($msg -match '^(?i)Lance:\s*(.+)$') {
        return ("J'ouvre {0}." -f $Matches[1].Trim())
    }
    if ($msg -match '^(?i)Ferme:\s*(.+)$') {
        return ("{0} est ferme." -f $Matches[1].Trim())
    }
    if ($msg -match '^(?i)Application introuvable:\s*(.+)$') {
        return ("Je ne trouve pas {0}." -f $Matches[1].Trim())
    }
    if ($msg -match '^(?i)Aucun process pour:\s*(.+)$') {
        return ("{0} n'est pas ouvert." -f $Matches[1].Trim())
    }
    if ($msg -match '^(?i)Alias inconnu:\s*(.+)$') {
        return ("Je ne connais pas l'application {0}." -f $Matches[1].Trim())
    }
    if ($msg -match '^(?i)Recherche:\s*(.+)$') {
        return ("Je cherche {0}." -f $Matches[1].Trim())
    }
    if ($msg -match '^(?i)YouTube:\s*(.+)$') {
        return ("Je cherche {0} sur YouTube." -f $Matches[1].Trim())
    }
    if ($msg -match '^(?i)Volume:\s*(.+)$') {
        $a = $Matches[1].Trim().ToLowerInvariant()
        if ($a -eq 'mute') { return 'Son coupe.' }
        if ($a -eq 'unmute') { return 'Son reactive.' }
        if ($a -eq 'up') { return 'Volume augmente.' }
        if ($a -eq 'down') { return 'Volume baisse.' }
        return ("Volume : {0}." -f $a)
    }
    if ($msg -match '^(?i)Theme\s+(\w+)\s+active') {
        $t = $Matches[1].ToLowerInvariant()
        if ($t -eq 'dark') { return 'Theme sombre active.' }
        if ($t -eq 'light') { return 'Theme clair active.' }
        return $msg
    }
    if ($msg -match '(?i)Confirmation requise') {
        return 'Dis oui pour confirmer, ou annule.'
    }
    return $msg
}

function Invoke-FreshAgentSpeakSkillResult {
    param(
        $Result,
        $AiConfig,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    if (-not (Test-FreshAgentShouldSpeakSkillResults -AiConfig $AiConfig)) { return }
    if (-not $Result) { return }
    $text = ConvertTo-FreshAgentSpokenSkillLine -Result $Result
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    Invoke-FreshAgentSpeak -Text $text -AiConfig $AiConfig -FreshAppData $FreshAppData | Out-Null
}
