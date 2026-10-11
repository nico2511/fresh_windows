#Requires -Version 5.1
<#
  Host detache pour voice_worker.exe.
  Isole le pipe stdout du process tray WinForms (sinon plantage STA).
  Protocol fichiers sous FreshAppData:
    - fa-voice-cmd.jsonl   : commandes JSON une par ligne
    - fa-voice-status.json : etat pret/recording/error/needRearm
    - fa-stt-pending.txt   : transcript a traiter par l'agent
    - fa-stt.paused        : si present, ignore transcripts (TTS)
#>
param(
    [Parameter(Mandatory)][string]$FreshAppData,
    [string]$ExePath = '',
    [string]$Language = 'fr',
    [string]$ModelSize = 'small',
    [string]$TranscriptionProfile = 'accurate'
)

$ErrorActionPreference = 'Continue'
$logPath = Join-Path $FreshAppData 'voice-worker-host.log'
$cmdPath = Join-Path $FreshAppData 'fa-voice-cmd.jsonl'
$statusPath = Join-Path $FreshAppData 'fa-voice-status.json'
$pendingPath = Join-Path $FreshAppData 'fa-stt-pending.txt'
$pausePath = Join-Path $FreshAppData 'fa-stt.paused'
$pidPath = Join-Path $FreshAppData 'fa-voice-host.pid'

# File-backed event queue (thread-safe enough for Append + Read/Clear)
$evtPath = Join-Path $FreshAppData 'fa-voice-events.jsonl'
$script:HostReady = $false
$script:HostModelLoaded = $false
$script:HostRecording = $false
$script:HostMicError = $false
$script:HostNeedRearm = $false
$script:HostPushToTalk = $false
$script:HostLastTranscriptAt = $null
$script:HostRearmAfter = $null
$script:HostShutdown = $false

function Write-HostLog([string]$Message) {
    try {
        Add-Content -LiteralPath $logPath -Value ('{0} HOST {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    catch { }
}

function Write-HostStatus {
    $payload = @{
        ready            = [bool]$script:HostReady
        modelLoaded      = [bool]$script:HostModelLoaded
        recording        = [bool]$script:HostRecording
        micError         = [bool]$script:HostMicError
        needRearm        = [bool]$script:HostNeedRearm
        lastTranscriptAt = $script:HostLastTranscriptAt
        hostPid          = $PID
        at               = (Get-Date).ToString('o')
    }
    try {
        ($payload | ConvertTo-Json -Compress) | Set-Content -LiteralPath $statusPath -Encoding UTF8
    }
    catch { }
}

function Process-HostEventLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    try { $evt = $Line | ConvertFrom-Json } catch { return }
    $type = [string]$evt.type
    switch ($type) {
        'ready' {
            $script:HostReady = $true
            Write-HostLog 'ready'
        }
        'model' {
            if ($evt.loaded) {
                $script:HostModelLoaded = $true
                Write-HostLog 'model loaded'
            }
        }
        'error' {
            $msg = [string]$evt.message
            Write-HostLog "worker error: $msg"
            if ($msg -match '(?i)micro|microphone|portaudio|device') { $script:HostMicError = $true }
        }
        'transcript' {
            $text = [string]$evt.text
            $script:HostRecording = $false
            $paused = Test-Path -LiteralPath $pausePath
            $pendingConfirm = Test-Path -LiteralPath (Join-Path $FreshAppData 'pending-confirm.json')
            $isConfirmWord = $false
            if ($pendingConfirm -and -not [string]::IsNullOrWhiteSpace($text)) {
                $tn = $text.Trim().ToLowerInvariant() -replace '[^\p{L}\s]', '' -replace '\s+', ' '
                if ($tn -match '^(oui|ouais|ok|non|annule|annuler|yes|go|confirme|valide)$') {
                    $isConfirmWord = $true
                }
            }
            if ($paused -and -not $isConfirmWord) {
                Write-HostLog "transcript ignored (paused): $text"
            }
            elseif (-not [string]::IsNullOrWhiteSpace($text)) {
                try {
                    Set-Content -LiteralPath $pendingPath -Value $text.Trim() -Encoding UTF8
                    $script:HostLastTranscriptAt = (Get-Date).ToString('o')
                    if ($isConfirmWord) {
                        Write-HostLog "transcript queued (confirm override): $text"
                        try { Remove-Item -LiteralPath $pausePath -Force -ErrorAction SilentlyContinue } catch { }
                    }
                    else {
                        Write-HostLog "transcript queued: $text"
                    }
                }
                catch {
                    Write-HostLog ("transcript write fail: $($_.Exception.Message)")
                }
            }
            # Always-on: re-armer apres utterance. PTT: attendre le prochain appui.
            if (-not $script:HostPushToTalk) {
                $script:HostNeedRearm = $true
                $script:HostRearmAfter = (Get-Date).AddMilliseconds(400)
            }
            else {
                $script:HostNeedRearm = $false
                $script:HostRearmAfter = $null
            }
        }
        'recording' {
            $script:HostRecording = [bool]$evt.active
            Write-HostLog ("recording=$($script:HostRecording)")
        }
        default {
            Write-HostLog ("evt: $type")
        }
    }
    Write-HostStatus
}

try {
    Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII
    foreach ($f in @($cmdPath, $evtPath)) {
        try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch { }
    }

    if ([string]::IsNullOrWhiteSpace($ExePath) -or -not (Test-Path -LiteralPath $ExePath)) {
        $ExePath = Join-Path $FreshAppData 'bin\voice_worker.exe'
    }
    if (-not (Test-Path -LiteralPath $ExePath)) {
        Write-HostLog "exe missing: $ExePath"
        exit 2
    }

    Write-HostLog "start exe=$ExePath"

    # Pump C# : les ScriptBlock PowerShell sur threads/DataReceived tuent le process (exit 5).
    if (-not ('FreshAgent.VoiceLinePump' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
namespace FreshAgent {
  public static class VoiceLinePump {
    public static ConcurrentQueue<string> Attach(Process proc) {
      var q = new ConcurrentQueue<string>();
      proc.OutputDataReceived += (s, e) => {
        if (e != null && !string.IsNullOrWhiteSpace(e.Data)) q.Enqueue(e.Data);
      };
      proc.ErrorDataReceived += (s, e) => {
        if (e != null && !string.IsNullOrWhiteSpace(e.Data)) q.Enqueue("STDERR:" + e.Data);
      };
      proc.BeginOutputReadLine();
      proc.BeginErrorReadLine();
      return q;
    }
  }
}
'@
    }

    $binDir = Split-Path -Parent $ExePath
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ExePath
    $psi.WorkingDirectory = $binDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $stdin = $proc.StandardInput
    $script:OutQueue = [FreshAgent.VoiceLinePump]::Attach($proc)

    function Send-Worker([hashtable]$Payload) {
        try {
            $line = ($Payload | ConvertTo-Json -Compress -Depth 6)
            $stdin.WriteLine($line)
            $stdin.Flush()
            return $true
        }
        catch {
            Write-HostLog ("send fail: $($_.Exception.Message)")
            return $false
        }
    }

    Start-Sleep -Milliseconds 250
    # Enrichir depuis agent-ai.json local (prompt FR + timings) si present
    $initialPrompt = 'Commandes PC en francais: lance Steam, lance Discord, lance Grok Bot, lance Cursor, ouvre Chrome, nettoyage.'
    $maxRec = 8
    $silenceMs = 700
    $minRec = 400
    $modelsDir = ''
    # Reutiliser le cache modeles CyberScribe si present
    foreach ($cand in @(
            'D:\models\cyberscribe_models',
            (Join-Path $env:LOCALAPPDATA 'Programs\CyberScribe\models')
        )) {
        if ($cand -and (Test-Path -LiteralPath $cand)) { $modelsDir = $cand; break }
    }
    try {
        $csCfgPath = Join-Path $env:LOCALAPPDATA 'Programs\CyberScribe\config.json'
        if (Test-Path -LiteralPath $csCfgPath) {
            $cs = Get-Content -LiteralPath $csCfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cs.models_dir -and (Test-Path -LiteralPath ([string]$cs.models_dir))) {
                $modelsDir = [string]$cs.models_dir
            }
        }
    }
    catch { }
    try {
        $aiPath = Join-Path $FreshAppData 'configs\agent-ai.json'
        $userAi = Join-Path $FreshAppData 'agent-ai.user.json'
        $stt = $null
        if (Test-Path -LiteralPath $aiPath) {
            $stt = (Get-Content -LiteralPath $aiPath -Raw -Encoding UTF8 | ConvertFrom-Json).stt
        }
        if (Test-Path -LiteralPath $userAi) {
            $u = Get-Content -LiteralPath $userAi -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($u.stt) {
                foreach ($p in $u.stt.PSObject.Properties) {
                    if ($null -eq $stt) { $stt = [pscustomobject]@{} }
                    $stt | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
                }
            }
        }
        if ($stt) {
            if ($stt.language) { $Language = [string]$stt.language }
            if ($stt.modelSize) { $ModelSize = [string]$stt.modelSize }
            if ($stt.transcriptionProfile) { $TranscriptionProfile = [string]$stt.transcriptionProfile }
            if ($stt.initialPrompt) { $initialPrompt = [string]$stt.initialPrompt }
            if ($stt.modelsDir -and (Test-Path -LiteralPath ([string]$stt.modelsDir))) {
                $modelsDir = [string]$stt.modelsDir
            }
            if ($null -ne $stt.maxRecordSeconds) { $maxRec = [int]$stt.maxRecordSeconds }
            elseif ($null -ne $stt.listenSeconds) { $maxRec = [int]$stt.listenSeconds }
            if ($null -ne $stt.silenceMs) { $silenceMs = [int]$stt.silenceMs }
            if ($null -ne $stt.minRecordMs) { $minRec = [int]$stt.minRecordMs }
            if ($null -ne $stt.pushToTalk) {
                $script:HostPushToTalk = [bool]$stt.pushToTalk
            }
            elseif ($stt.listenMode) {
                $script:HostPushToTalk = ([string]$stt.listenMode -eq 'pushToTalk')
            }
        }
    }
    catch {
        Write-HostLog ("stt config read: $($_.Exception.Message)")
    }

    # PTT: enregistre jusqu'au relachement (pas de coupe silence precoce).
    if ($script:HostPushToTalk) {
        if ($maxRec -lt 30) { $maxRec = 30 }
        if ($silenceMs -lt 60000) { $silenceMs = 60000 }
        Write-HostLog ("mode=pushToTalk max=${maxRec}s silenceMs=$silenceMs")
    }
    else {
        Write-HostLog 'mode=alwaysOn'
    }

    # Completer le prompt avec apps Start Menu (vocabulaire reel, pas des alias inventes)
    try {
        $lnkNames = @()
        foreach ($root in @(
                (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
                (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
            )) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 40 |
                ForEach-Object { $lnkNames += [IO.Path]::GetFileNameWithoutExtension($_.Name) }
        }
        if ($lnkNames.Count -gt 0) {
            $sample = ($lnkNames | Select-Object -First 12) -join ', '
            $initialPrompt = "$initialPrompt Lance: $sample."
        }
    }
    catch { }

    $preloadCfg = @{
        language              = $Language
        model_size            = $ModelSize
        device                = 'auto'
        compute_type          = 'int8'
        transcription_profile = $TranscriptionProfile
        max_record_seconds    = $maxRec
        silence_ms            = $silenceMs
        min_record_ms         = $minRec
        initial_prompt        = $initialPrompt
        hotwords              = $initialPrompt
        # Desactive le conditionnement sur le texte precedent (reduit les hallucinations enchainees)
        condition_on_previous_text = $false
    }
    if ($modelsDir) {
        $preloadCfg.models_dir = $modelsDir
        Write-HostLog "models_dir=$modelsDir"
    }
    Send-Worker @{
        cmd    = 'preload'
        config = $preloadCfg
    } | Out-Null
    Write-HostStatus
    Write-HostLog ("preload sent model=$ModelSize profile=$TranscriptionProfile max=${maxRec}s - waiting ready/model")

    while (-not $script:HostShutdown) {
        if ($proc.HasExited) {
            Write-HostLog "worker exited code=$($proc.ExitCode)"
            break
        }

        # Drain queue C#
        $line = $null
        while ($script:OutQueue.TryDequeue([ref]$line)) {
            if ($line -like 'STDERR:*') {
                Write-HostLog ('stderr: ' + $line.Substring(7))
            }
            else {
                Process-HostEventLine -Line $line
            }
        }

        # Agent commands
        if (Test-Path -LiteralPath $cmdPath) {
            try {
                $cmds = @(Get-Content -LiteralPath $cmdPath -Encoding UTF8 -ErrorAction SilentlyContinue)
                Clear-Content -LiteralPath $cmdPath -ErrorAction SilentlyContinue
                foreach ($raw in $cmds) {
                    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
                    try { $c = $raw | ConvertFrom-Json } catch { continue }
                    $cmdName = [string]$c.cmd
                    Write-HostLog "cmd: $cmdName"
                    if ($cmdName -eq 'shutdown') {
                        Send-Worker @{ cmd = 'shutdown' } | Out-Null
                        $script:HostShutdown = $true
                        break
                    }
                    if ($cmdName -eq 'toggle') {
                        Send-Worker @{ cmd = 'toggle' } | Out-Null
                        $script:HostNeedRearm = $false
                        $script:HostRearmAfter = $null
                        Write-HostStatus
                        continue
                    }
                    if ($cmdName -eq 'preload') {
                        Send-Worker @{ cmd = 'preload'; config = $c.config } | Out-Null
                        continue
                    }
                    if ($cmdName -eq 'ack_rearm') {
                        # Agent ack optionnel — le host auto-rearme aussi
                        continue
                    }
                    if ($cmdName -eq 'set_ptt') {
                        $script:HostPushToTalk = [bool]$c.enabled
                        if ($script:HostPushToTalk) {
                            $script:HostNeedRearm = $false
                            $script:HostRearmAfter = $null
                        }
                        Write-HostLog ("set_ptt=$($script:HostPushToTalk)")
                        Write-HostStatus
                        continue
                    }
                }
            }
            catch {
                Write-HostLog ("cmd loop: $($_.Exception.Message)")
            }
        }

        # Auto-rearm apres transcript (always-on uniquement)
        if ($script:HostNeedRearm -and -not $script:HostRecording -and -not $script:HostPushToTalk) {
            $paused = Test-Path -LiteralPath $pausePath
            if (-not $paused) {
                if ($script:HostRearmAfter -and ((Get-Date) -ge [datetime]$script:HostRearmAfter)) {
                    Write-HostLog 'auto-rearm toggle'
                    Send-Worker @{ cmd = 'toggle' } | Out-Null
                    $script:HostNeedRearm = $false
                    $script:HostRearmAfter = $null
                    Write-HostStatus
                }
            }
            else {
                # Pendant TTS: reporter le rearm
                $script:HostRearmAfter = (Get-Date).AddMilliseconds(400)
            }
        }

        # Heartbeat status pour que l'agent ne tue pas un host "fantome"
        if (-not $script:HostLastHeartbeatAt -or (((Get-Date) - [datetime]$script:HostLastHeartbeatAt).TotalSeconds -ge 3)) {
            $script:HostLastHeartbeatAt = Get-Date
            Write-HostStatus
        }

        Start-Sleep -Milliseconds 60
    }

    try {
        if (-not $proc.HasExited) { $proc.Kill() }
    }
    catch { }
    try { $proc.Dispose() } catch { }
    Write-HostLog 'host exit'
}
catch {
    Write-HostLog ("fatal: $($_.Exception.ToString())")
    exit 1
}
finally {
    try { Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue } catch { }
}
