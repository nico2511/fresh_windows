#Requires -Version 5.1
<#
  STT via voice_worker.exe (asset FreshWindows, protocole CyberScribeNote).
  Telecharge depuis les releases CyberScribeNote si absent — sans installer CyberScribeNote.
#>

function Get-FreshAgentVoiceWorkerPaths {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $bin = Join-Path $FreshAppData 'bin'
    return @{
        BinDir   = $bin
        Exe      = Join-Path $bin 'voice_worker.exe'
        ZipTemp  = Join-Path $FreshAppData 'cache\voice_worker_dl.zip'
        Extract  = Join-Path $FreshAppData 'cache\voice_worker_extract'
        Log      = Join-Path $FreshAppData 'voice-worker-host.log'
    }
}

function Write-FreshAgentVoiceWorkerLog {
    param([string]$Message, [string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $paths = Get-FreshAgentVoiceWorkerPaths -FreshAppData $FreshAppData
    try {
        Add-Content -LiteralPath $paths.Log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    catch { }
}

function Find-FreshAgentVoiceWorkerInTree {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return $null }
    $hit = Get-ChildItem -LiteralPath $Root -Recurse -Filter 'voice_worker.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Ensure-FreshAgentVoiceWorker {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        $AiConfig = $null
    )
    $paths = Get-FreshAgentVoiceWorkerPaths -FreshAppData $FreshAppData
    if (Test-Path -LiteralPath $paths.Exe) {
        return $paths.Exe
    }

    # Config override path
    if ($AiConfig -and $AiConfig.stt -and $AiConfig.stt.exe) {
        $cfgExe = [Environment]::ExpandEnvironmentVariables([string]$AiConfig.stt.exe)
        if ((Test-Path -LiteralPath $cfgExe) -and ($cfgExe -ne $paths.Exe)) {
            New-Item -ItemType Directory -Path $paths.BinDir -Force | Out-Null
            Copy-Item -LiteralPath $cfgExe -Destination $paths.Exe -Force
            return $paths.Exe
        }
    }

    $url = 'https://github.com/nico2511/CyberScribeNote/releases/latest/download/CyberScribeNote-win.zip'
    if ($AiConfig -and $AiConfig.stt -and $AiConfig.stt.downloadUrl) {
        $url = [string]$AiConfig.stt.downloadUrl
    }

    New-Item -ItemType Directory -Path $paths.BinDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path $paths.ZipTemp -Parent) -Force | Out-Null
    Write-FreshAgentVoiceWorkerLog -Message ("download $url") -FreshAppData $FreshAppData
    try {
        Invoke-WebRequest -Uri $url -OutFile $paths.ZipTemp -UseBasicParsing
    }
    catch {
        Write-FreshAgentVoiceWorkerLog -Message ("download failed: $($_.Exception.Message)") -FreshAppData $FreshAppData
        return $null
    }

    if (Test-Path -LiteralPath $paths.Extract) {
        Remove-Item -LiteralPath $paths.Extract -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $paths.Extract -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $paths.ZipTemp -DestinationPath $paths.Extract -Force
    }
    catch {
        Write-FreshAgentVoiceWorkerLog -Message ("extract failed: $($_.Exception.Message)") -FreshAppData $FreshAppData
        return $null
    }

    $found = Find-FreshAgentVoiceWorkerInTree -Root $paths.Extract
    if (-not $found) {
        Write-FreshAgentVoiceWorkerLog -Message 'voice_worker.exe absent from zip' -FreshAppData $FreshAppData
        return $null
    }
    Copy-Item -LiteralPath $found -Destination $paths.Exe -Force
    Write-FreshAgentVoiceWorkerLog -Message ("installed $($paths.Exe)") -FreshAppData $FreshAppData
    return $paths.Exe
}

function Test-FreshAgentVoiceWorkerReady {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $paths = Get-FreshAgentVoiceWorkerPaths -FreshAppData $FreshAppData
    return (Test-Path -LiteralPath $paths.Exe)
}

function Get-FreshAgentVoiceStatusMessage {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        $AiConfig = $null
    )
    if ($script:VoiceListenActive) { return 'STT : ecoute ON (voice_worker)' }
    $paths = Get-FreshAgentVoiceWorkerPaths -FreshAppData $FreshAppData
    if (Test-Path -LiteralPath $paths.Exe) { return 'STT : voice_worker pret (OFF)' }
    return 'STT : voice_worker non installe (Ecoute ON le telechargera)'
}

function Send-FreshAgentVoiceWorkerCmd {
    param(
        [hashtable]$Payload
    )
    if (-not $script:FaVoiceWorkerStdin) { return $false }
    try {
        $line = ($Payload | ConvertTo-Json -Compress -Depth 6)
        $script:FaVoiceWorkerStdin.WriteLine($line)
        $script:FaVoiceWorkerStdin.Flush()
        return $true
    }
    catch {
        Write-FreshAgentVoiceWorkerLog -Message ("send cmd failed: $($_.Exception.Message)")
        return $false
    }
}

function Start-FreshAgentVoiceWorkerProcess {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        $AiConfig = $null
    )
    if ($script:FaVoiceWorkerProc -and -not $script:FaVoiceWorkerProc.HasExited) {
        return $true
    }
    $exe = Ensure-FreshAgentVoiceWorker -FreshAppData $FreshAppData -AiConfig $AiConfig
    if (-not $exe) { return $false }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true
    $null = $proc.Start()
    $script:FaVoiceWorkerProc = $proc
    $script:FaVoiceWorkerStdin = $proc.StandardInput
    $script:FaVoiceWorkerLastActivity = Get-Date
    $script:FaVoiceWorkerReady = $false
    $script:FaVoiceWorkerModelLoaded = $false
    $script:FaVoiceWorkerMicError = $false

    $outHandler = [System.Diagnostics.DataReceivedEventHandler] {
        param($sender, $e)
        if ([string]::IsNullOrWhiteSpace($e.Data)) { return }
        $script:FaVoiceWorkerLastActivity = Get-Date
        try {
            $evt = $e.Data | ConvertFrom-Json
        }
        catch { return }
        $type = [string]$evt.type
        switch ($type) {
            'ready' { $script:FaVoiceWorkerReady = $true }
            'model' {
                if ($evt.loaded) { $script:FaVoiceWorkerModelLoaded = $true }
            }
            'error' {
                $msg = [string]$evt.message
                Write-FreshAgentVoiceWorkerLog -Message ("worker error: $msg")
                if ($msg -match '(?i)micro|microphone|portaudio|device') {
                    $script:FaVoiceWorkerMicError = $true
                }
            }
            'transcript' {
                $text = [string]$evt.text
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $pending = Join-Path $FreshAppData 'fa-stt-pending.txt'
                    Set-Content -LiteralPath $pending -Value $text.Trim() -Encoding UTF8
                    $script:FaVoiceWorkerLastTranscriptAt = Get-Date
                }
                $script:FaVoiceWorkerRecording = $false
                $script:FaVoiceWorkerNeedRearm = $true
            }
            'recording' {
                $script:FaVoiceWorkerRecording = [bool]$evt.active
            }
            default { }
        }
    }
    $proc.add_OutputDataReceived($outHandler)
    $proc.BeginOutputReadLine()

    $lang = 'fr'
    $model = 'base'
    $profile = 'fast'
    if ($AiConfig -and $AiConfig.stt) {
        if ($AiConfig.stt.language) { $lang = [string]$AiConfig.stt.language }
        if ($AiConfig.stt.modelSize) { $model = [string]$AiConfig.stt.modelSize }
        if ($AiConfig.stt.transcriptionProfile) { $profile = [string]$AiConfig.stt.transcriptionProfile }
    }
    $cfg = @{
        language               = $lang
        model_size             = $model
        device                 = 'auto'
        compute_type           = 'int8'
        transcription_profile  = $profile
        max_record_seconds     = 30
    }
    Start-Sleep -Milliseconds 200
    Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'preload'; config = $cfg } | Out-Null
    return $true
}

function Stop-FreshAgentVoiceWorkerProcess {
    try {
        Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'shutdown' } | Out-Null
    }
    catch { }
    Start-Sleep -Milliseconds 150
    if ($script:FaVoiceWorkerProc) {
        try {
            if (-not $script:FaVoiceWorkerProc.HasExited) {
                $script:FaVoiceWorkerProc.Kill()
            }
        }
        catch { }
        try { $script:FaVoiceWorkerProc.Dispose() } catch { }
    }
    $script:FaVoiceWorkerProc = $null
    $script:FaVoiceWorkerStdin = $null
    $script:FaVoiceWorkerReady = $false
    $script:FaVoiceWorkerRecording = $false
    $script:FaVoiceWorkerNeedRearm = $false
}

function Start-FreshAgentVoiceListenSession {
    param(
        [string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }),
        $AiConfig = $null
    )
    if ($script:VoiceListenActive) { return }
    if (-not $AiConfig -and (Get-Command Get-FreshAgentAiConfig -ErrorAction SilentlyContinue)) {
        $AiConfig = Get-FreshAgentAiConfig -RepoRef $(if ($script:RepoRef) { $script:RepoRef } else { 'main' }) -FreshAppData $FreshAppData -PreferLocal
    }
    if (-not (Start-FreshAgentVoiceWorkerProcess -FreshAppData $FreshAppData -AiConfig $AiConfig)) {
        if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
            Show-FreshAgentUserNotice -Title 'STT' -Text 'Impossible de preparer voice_worker.' -Level Warning
        }
        return
    }
    $script:VoiceListenActive = $true
    $script:VoiceAlwaysOn = $true
    $script:FaVoiceWorkerMicError = $false
    $script:FaVoiceWorkerLastTranscriptAt = Get-Date
    $script:FaVoiceListenStartedAt = Get-Date
    Remove-Item -LiteralPath (Join-Path $FreshAppData 'fa-stt.paused') -Force -ErrorAction SilentlyContinue

    # Demarre une premiere dictée (toggle = start)
    Start-Sleep -Milliseconds 400
    Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'toggle' } | Out-Null
    $script:FaVoiceWorkerNeedRearm = $false

    if (Get-Command Start-FreshAgentSttPollTimerIfNeeded -ErrorAction SilentlyContinue) {
        Start-FreshAgentSttPollTimerIfNeeded
    }
    if (Get-Command Start-FreshAgentVoiceWatchTimerIfNeeded -ErrorAction SilentlyContinue) {
        Start-FreshAgentVoiceWatchTimerIfNeeded
    }
    if ($script:MiAiListenItem) { $script:MiAiListenItem.Text = 'Ecoute : ON (clic = OFF)' }
    if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
        Show-FreshAgentUserNotice -Title 'Ecoute' -Text 'Active — parlez pour une commande.' -Level Info
    }
    if (Get-Command Start-FreshAgentQuickSpeak -ErrorAction SilentlyContinue) {
        Start-FreshAgentQuickSpeak -Text 'Ecoute active.'
    }
}

function Stop-FreshAgentVoiceListenSession {
    $script:VoiceListenActive = $false
    $script:VoiceAlwaysOn = $false
    $script:FaVoiceWorkerNeedRearm = $false
    if ($script:FaVoiceWorkerRecording) {
        Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'toggle' } | Out-Null
        Start-Sleep -Milliseconds 100
    }
    Stop-FreshAgentVoiceWorkerProcess
    if ($script:MiAiListenItem) { $script:MiAiListenItem.Text = 'Ecoute : OFF' }
    if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
        Show-FreshAgentUserNotice -Title 'Ecoute' -Text 'Coupee.' -Level Info
    }
}

function Invoke-FreshAgentVoiceWatchTick {
    param(
        [string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }),
        $AiConfig = $null
    )
    if (-not $script:VoiceListenActive) { return }
    if (-not $AiConfig -and (Get-Command Get-FreshAgentAiConfig -ErrorAction SilentlyContinue)) {
        $AiConfig = Get-FreshAgentAiConfig -RepoRef $(if ($script:RepoRef) { $script:RepoRef } else { 'main' }) -FreshAppData $FreshAppData -PreferLocal
    }

    # Auto-coupe : conflit micro
    $releaseMic = $true
    if ($AiConfig -and $AiConfig.voice -and $null -ne $AiConfig.voice.releaseOnMicConflict) {
        $releaseMic = [bool]$AiConfig.voice.releaseOnMicConflict
    }
    if ($releaseMic -and $script:FaVoiceWorkerMicError) {
        Stop-FreshAgentVoiceListenSession
        if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
            Show-FreshAgentUserNotice -Title 'Ecoute' -Text 'Coupee (micro occupe).' -Level Warning
        }
        return
    }

    # Auto-coupe : idle
    $idleMin = 5
    if ($AiConfig -and $AiConfig.voice -and $null -ne $AiConfig.voice.idleMinutes) {
        $idleMin = [int]$AiConfig.voice.idleMinutes
    }
    $last = $script:FaVoiceWorkerLastTranscriptAt
    if (-not $last) { $last = $script:FaVoiceListenStartedAt }
    if ($last -and $idleMin -gt 0) {
        $idle = ((Get-Date) - [datetime]$last).TotalMinutes
        if ($idle -ge $idleMin) {
            Stop-FreshAgentVoiceListenSession
            if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
                Show-FreshAgentUserNotice -Title 'Ecoute' -Text 'Coupee (inactivite).' -Level Info
            }
            return
        }
    }

    # Process mort
    if ($script:FaVoiceWorkerProc -and $script:FaVoiceWorkerProc.HasExited) {
        Stop-FreshAgentVoiceListenSession
        return
    }

    # Rearm utterance si session encore ON
    if ($script:FaVoiceWorkerNeedRearm -and -not $script:FaVoiceWorkerRecording) {
        $script:FaVoiceWorkerNeedRearm = $false
        Start-Sleep -Milliseconds 250
        Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'toggle' } | Out-Null
    }
}

function Start-FreshAgentVoiceWatchTimerIfNeeded {
    if ($script:FaVoiceWatchTimer) { return }
    $script:FaVoiceWatchTimer = New-Object System.Windows.Forms.Timer
    $script:FaVoiceWatchTimer.Interval = 800
    $script:FaVoiceWatchTimer.Add_Tick({
            try { Invoke-FreshAgentVoiceWatchTick } catch { }
        })
    $script:FaVoiceWatchTimer.Start()
}
