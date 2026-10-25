#Requires -Version 5.1
<#
  STT via voice_worker.exe (asset FreshWindows, protocole CyberScribeNote).
  Telecharge depuis les releases CyberScribeNote si absent — sans installer CyberScribeNote.
#>

$sttSettingsLib = Join-Path $PSScriptRoot '..\lib\FreshAgent-SttSettings.ps1'
if (-not (Test-Path -LiteralPath $sttSettingsLib)) {
    $sttSettingsLib = Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\FreshAgent-SttSettings.ps1'
}
if (Test-Path -LiteralPath $sttSettingsLib) {
    . $sttSettingsLib
}

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

function Test-FreshAgentSttPushToTalk {
    param($AiConfig = $null)
    if (-not $AiConfig -and (Get-Command Get-FreshAgentAiConfig -ErrorAction SilentlyContinue)) {
        try {
            $AiConfig = Get-FreshAgentAiConfig -RepoRef $(if ($script:RepoRef) { $script:RepoRef } else { 'main' }) `
                -FreshAppData $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }) -PreferLocal
        }
        catch { }
    }
    if (Get-Command Test-FreshAgentSttPushToTalkFromConfig -ErrorAction SilentlyContinue) {
        return Test-FreshAgentSttPushToTalkFromConfig -AiConfig $AiConfig
    }
    if (-not $AiConfig -or -not $AiConfig.stt) { return $true }
    if ($null -ne $AiConfig.stt.pushToTalk) { return [bool]$AiConfig.stt.pushToTalk }
    $mode = [string]$AiConfig.stt.listenMode
    if ($mode -eq 'alwaysOn') { return $false }
    if ($mode -eq 'pushToTalk') { return $true }
    return $true
}

function Get-FreshAgentPttHotkeyLabel {
    param($AiConfig = $null)
    $hk = 'Ctrl+Alt+Space'
    if ($AiConfig -and $AiConfig.stt -and $AiConfig.stt.pttHotkey) {
        $hk = [string]$AiConfig.stt.pttHotkey
    }
    if ([string]::IsNullOrWhiteSpace($hk)) { $hk = 'Ctrl+Alt+Space' }
    return $hk.Trim()
}

function Get-FreshAgentPttHotkeyChoices {
    return @(
        'Ctrl+Alt+Space',
        'Ctrl+Shift+Space',
        'Ctrl+Space',
        'Alt+Space',
        'Ctrl+Alt+V',
        'Ctrl+Shift+V',
        'Pause',
        'ScrollLock',
        'Insert',
        'F8',
        'F9',
        'F10',
        'F12'
    )
}

function Normalize-FreshAgentPttHotkeyLabel {
    param([string]$Hotkey)
    if ([string]::IsNullOrWhiteSpace($Hotkey)) { return 'Ctrl+Alt+Space' }
    $parts = @($Hotkey -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -lt 1) { return 'Ctrl+Alt+Space' }
    $norm = New-Object System.Collections.Generic.List[string]
    $key = $null
    foreach ($p in $parts) {
        switch -Regex ($p) {
            '^(?i)(ctrl|control)$' { [void]$norm.Add('Ctrl'); continue }
            '^(?i)(alt|menu)$' { [void]$norm.Add('Alt'); continue }
            '^(?i)(shift)$' { [void]$norm.Add('Shift'); continue }
            '^(?i)(win|windows|lwin)$' { [void]$norm.Add('Win'); continue }
            default {
                $key = $p.Substring(0, 1).ToUpperInvariant() + $(if ($p.Length -gt 1) { $p.Substring(1).ToLowerInvariant() } else { '' })
                if ($p -match '^(?i)f([1-9]|1[0-2])$') { $key = 'F' + $Matches[1] }
                elseif ($p -match '^(?i)space$') { $key = 'Space' }
                elseif ($p -match '^(?i)pause$') { $key = 'Pause' }
                elseif ($p -match '^(?i)scrolllock$') { $key = 'ScrollLock' }
                elseif ($p -match '^(?i)insert$') { $key = 'Insert' }
                elseif ($p.Length -eq 1) { $key = $p.ToUpperInvariant() }
            }
        }
    }
    if (-not $key) { $key = 'Space' }
    # Unique modifiers, keep order Ctrl Alt Shift Win
    $order = @('Ctrl', 'Alt', 'Shift', 'Win')
    $mods = @($order | Where-Object { $norm -contains $_ })
    return (($mods + $key) -join '+')
}

function Get-FreshAgentPttHotkeySpec {
    param([string]$Hotkey = 'Ctrl+Alt+Space')
    $Hotkey = Normalize-FreshAgentPttHotkeyLabel -Hotkey $Hotkey
    $mods = New-Object System.Collections.Generic.List[int]
    $vk = 0x20 # Space
    $parts = @($Hotkey -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($p in $parts) {
        switch -Regex ($p) {
            '^(?i)(ctrl|control)$' { [void]$mods.Add(0x11); continue }
            '^(?i)(alt|menu)$' { [void]$mods.Add(0x12); continue }
            '^(?i)(shift)$' { [void]$mods.Add(0x10); continue }
            '^(?i)(win|windows|lwin)$' { [void]$mods.Add(0x5B); continue }
            '^(?i)space$' { $vk = 0x20; continue }
            '^(?i)pause$' { $vk = 0x13; continue }
            '^(?i)scrolllock$' { $vk = 0x91; continue }
            '^(?i)insert$' { $vk = 0x2D; continue }
            '^(?i)home$' { $vk = 0x24; continue }
            '^(?i)end$' { $vk = 0x23; continue }
            '^(?i)f([1-9]|1[0-2])$' {
                $n = [int]$Matches[1]
                $vk = 0x70 + ($n - 1)
                continue
            }
            default {
                if ($p.Length -eq 1) {
                    $ch = $p.ToUpperInvariant()[0]
                    if ($ch -ge [char]'A' -and $ch -le [char]'Z') { $vk = [int][char]$ch }
                    elseif ($ch -ge [char]'0' -and $ch -le [char]'9') { $vk = [int][char]$ch }
                }
            }
        }
    }
    return @{
        Vk        = [int]$vk
        Modifiers = @($mods)
        Label     = $Hotkey
    }
}

function Apply-FreshAgentPttHotkeyLive {
    param(
        [Parameter(Mandatory)][string]$Hotkey,
        $AiConfig = $null
    )
    $label = Normalize-FreshAgentPttHotkeyLabel -Hotkey $Hotkey
    $script:FaPttHotkeySpec = Get-FreshAgentPttHotkeySpec -Hotkey $label
    return $label
}

function Show-FreshAgentPttHotkeyPicker {
    param(
        [string]$Current = 'Ctrl+Alt+Space',
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $Current = Normalize-FreshAgentPttHotkeyLabel -Hotkey $Current
    $choices = @(Get-FreshAgentPttHotkeyChoices)
    if ($choices -notcontains $Current) { $choices = @($Current) + $choices }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Raccourci Push-to-talk'
    $form.Size = New-Object System.Drawing.Size(420, 360)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Choisis un raccourci a maintenir pour parler (PTT) :'
    $lbl.Location = New-Object System.Drawing.Point(12, 12)
    $lbl.Size = New-Object System.Drawing.Size(380, 24)
    $form.Controls.Add($lbl) | Out-Null

    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(12, 40)
    $list.Size = New-Object System.Drawing.Size(380, 180)
    foreach ($c in $choices) { [void]$list.Items.Add($c) }
    $idx = $list.Items.IndexOf($Current)
    if ($idx -ge 0) { $list.SelectedIndex = $idx } else { $list.SelectedIndex = 0 }
    $form.Controls.Add($list) | Out-Null

    $lblCustom = New-Object System.Windows.Forms.Label
    $lblCustom.Text = 'Ou personnalise (ex: Ctrl+Alt+Q) :'
    $lblCustom.Location = New-Object System.Drawing.Point(12, 230)
    $lblCustom.Size = New-Object System.Drawing.Size(380, 20)
    $form.Controls.Add($lblCustom) | Out-Null

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(12, 252)
    $txt.Size = New-Object System.Drawing.Size(380, 24)
    $txt.Text = $Current
    $form.Controls.Add($txt) | Out-Null

    $list.Add_SelectedIndexChanged({
            if ($list.SelectedItem) { $txt.Text = [string]$list.SelectedItem }
        })

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'OK'
    $btnOk.Location = New-Object System.Drawing.Point(216, 288)
    $btnOk.Size = New-Object System.Drawing.Size(86, 28)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnOk) | Out-Null
    $form.AcceptButton = $btnOk

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Annuler'
    $btnCancel.Location = New-Object System.Drawing.Point(306, 288)
    $btnCancel.Size = New-Object System.Drawing.Size(86, 28)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel) | Out-Null
    $form.CancelButton = $btnCancel

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    $picked = if (-not [string]::IsNullOrWhiteSpace($txt.Text)) { $txt.Text } else { [string]$list.SelectedItem }
    return (Normalize-FreshAgentPttHotkeyLabel -Hotkey $picked)
}

function Ensure-FreshAgentPttKeysType {
    if ('FreshAgentPttKeys' -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FreshAgentPttKeys {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
    public static bool IsDown(int vKey) {
        return (GetAsyncKeyState(vKey) & 0x8000) != 0;
    }
}
"@
}

function Test-FreshAgentPttHotkeyDown {
    param([hashtable]$Spec)
    if (-not $Spec) { return $false }
    Ensure-FreshAgentPttKeysType
    foreach ($m in @($Spec.Modifiers)) {
        if (-not [FreshAgentPttKeys]::IsDown([int]$m)) { return $false }
    }
    return [FreshAgentPttKeys]::IsDown([int]$Spec.Vk)
}

function Get-FreshAgentVoiceStatusMessage {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        $AiConfig = $null
    )
    $ptt = Test-FreshAgentSttPushToTalk -AiConfig $AiConfig
    $hk = Get-FreshAgentPttHotkeyLabel -AiConfig $AiConfig
    if ($script:VoiceListenActive) {
        if ($ptt) { return ("STT : PTT ON ($hk)") }
        return 'STT : ecoute ON (toujours actif)'
    }
    $paths = Get-FreshAgentVoiceWorkerPaths -FreshAppData $FreshAppData
    if (Test-Path -LiteralPath $paths.Exe) {
        if ($ptt) { return ("STT : PTT pret OFF ($hk)") }
        return 'STT : voice_worker pret (OFF)'
    }
    return 'STT : voice_worker non installe (Ecoute ON le telechargera)'
}

function Send-FreshAgentVoiceWorkerCmd {
    param(
        [hashtable]$Payload,
        [string]$FreshAppData = $(if ($script:FaVoiceWorkerAppData) { $script:FaVoiceWorkerAppData } elseif ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot })
    )
    # Protocol fichier vers FreshAgent-VoiceHost.ps1 (pas de pipe dans le process tray).
    try {
        $cmdPath = Join-Path $FreshAppData 'fa-voice-cmd.jsonl'
        $line = ($Payload | ConvertTo-Json -Compress -Depth 6)
        Add-Content -LiteralPath $cmdPath -Value $line -Encoding UTF8
        return $true
    }
    catch {
        Write-FreshAgentVoiceWorkerLog -Message ("send cmd failed: $($_.Exception.Message)") -FreshAppData $FreshAppData
        return $false
    }
}

function Send-FreshAgentVoiceRecordStart {
    param([string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }))
    if ($script:FaVoiceTranscribing) { return $false }
    if ($script:FaVoiceWorkerRecording) { return $false }
    return Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'record_start' } -FreshAppData $FreshAppData
}

function Send-FreshAgentVoiceRecordStop {
    param([string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }))
    if ($script:FaVoiceTranscribing) { return $false }
    if (-not $script:FaVoiceWorkerRecording) { return $false }
    return Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'record_stop' } -FreshAppData $FreshAppData
}

function Sync-FreshAgentVoiceHostStatus {
    param([string]$FreshAppData = $(if ($script:FaVoiceWorkerAppData) { $script:FaVoiceWorkerAppData } elseif ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }))
    $statusPath = Join-Path $FreshAppData 'fa-voice-status.json'
    if (-not (Test-Path -LiteralPath $statusPath)) { return }
    try {
        $st = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:FaVoiceWorkerReady = [bool]$st.ready
        $script:FaVoiceWorkerModelLoaded = [bool]$st.modelLoaded
        $script:FaVoiceWorkerRecording = [bool]$st.recording
        if ($null -ne $st.transcribing) { $script:FaVoiceTranscribing = [bool]$st.transcribing }
        $script:FaVoiceWorkerMicError = [bool]$st.micError
        if ($st.needRearm) { $script:FaVoiceWorkerNeedRearm = $true }
        if ($st.lastTranscriptAt) {
            try { $script:FaVoiceWorkerLastTranscriptAt = [datetime]$st.lastTranscriptAt } catch { }
        }
        $script:FaVoiceWorkerLastActivity = Get-Date
    }
    catch { }
}

function Test-FreshAgentSttTranscriptUseful {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $t = $Text.Trim()
    # Ignore bruit / hallucinations Whisper (always-on capture le silence)
    if ($t.Length -lt 3) { return $false }
    $letters = ([regex]::Matches($t, '\p{L}')).Count
    if ($letters -lt 3) { return $false }
    $norm = $t.ToLowerInvariant() -replace '[^\p{L}\p{N}\s]', '' -replace '\s+', ' '
    $norm = $norm.Trim()
    # Ne pas filtrer oui/non/ok : utilises pour confirmer les actions sensibles.
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
    # Repetitions type "L'Oss, L'Oss" / "Stimme. Stimme."
    $parts = @($norm -split '\s+' | Where-Object { $_ })
    if ($parts.Count -ge 2) {
        $uniq = @($parts | Select-Object -Unique)
        if ($uniq.Count -eq 1 -and $parts[0].Length -le 8) { return $false }
    }
    # Un seul token tres court sans verbe d'action
    if ($parts.Count -eq 1 -and $parts[0].Length -le 4 -and $parts[0] -notmatch '^(oui|non|ok|go)$') {
        return $false
    }
    return $true
}

function Test-FreshAgentVoiceListenPaused {
    param([string]$FreshAppData = $(if ($script:FaVoiceWorkerAppData) { $script:FaVoiceWorkerAppData } elseif ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }))
    if ($global:FreshAgentSttPaused) { return $true }
    $pauseFile = Join-Path $FreshAppData 'fa-stt.paused'
    return (Test-Path -LiteralPath $pauseFile)
}

function Suspend-FreshAgentVoiceListenForTts {
    param(
        [string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }),
        [int]$ResumeAfterSeconds = 8
    )
    $global:FreshAgentSttPaused = $true
    try { Set-Content -LiteralPath (Join-Path $FreshAppData 'fa-stt.paused') -Value '1' -Encoding ASCII } catch { }
    $script:SttUnpauseAt = (Get-Date).AddSeconds([Math]::Max(4, $ResumeAfterSeconds))
    $script:FaVoiceWorkerNeedRearm = $false
    # Coupe vraiment l'enregistrement en cours (sinon le micro capte le TTS).
    if ($script:FaVoiceWorkerRecording) {
        if (Get-Command Send-FreshAgentVoiceRecordStop -ErrorAction SilentlyContinue) {
            Send-FreshAgentVoiceRecordStop -FreshAppData $FreshAppData | Out-Null
        }
        else {
            Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'toggle' } | Out-Null
        }
    }
}

function Resume-FreshAgentVoiceListenAfterPause {
    param([string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }))
    $global:FreshAgentSttPaused = $false
    Remove-Item -LiteralPath (Join-Path $FreshAppData 'fa-stt.paused') -Force -ErrorAction SilentlyContinue
    $script:SttUnpauseAt = $null
    $ptt = $false
    try { $ptt = Test-FreshAgentSttPushToTalk } catch { }
    # Always-on: re-armer. PTT: attendre le prochain appui.
    if ($script:VoiceListenActive -and -not $script:FaVoiceWorkerRecording -and -not $ptt) {
        $script:FaVoiceWorkerNeedRearm = $true
    }
}

function Test-FreshAgentVoiceHostAlive {
    param(
        [System.Diagnostics.Process]$Proc = $null,
        [string]$FreshAppData = $(if ($script:FaVoiceWorkerAppData) { $script:FaVoiceWorkerAppData } elseif ($script:FreshAppData) { $script:FreshAppData } else { $null })
    )
    if (-not $Proc) { $Proc = $script:FaVoiceWorkerProc }
    # 1) Heartbeat: status JSON recent = host vivant (meme si HasExited ment)
    if ($FreshAppData) {
        $statusPath = Join-Path $FreshAppData 'fa-voice-status.json'
        if (Test-Path -LiteralPath $statusPath) {
            try {
                $ageSec = ((Get-Date) - (Get-Item -LiteralPath $statusPath).LastWriteTime).TotalSeconds
                if ($ageSec -ge 0 -and $ageSec -lt 20) { return $true }
            }
            catch { }
        }
    }
    # 2) PIDs connus encore listes par l'OS (sans se fier a .HasExited)
    $ids = @()
    if ($Proc) {
        try { $ids += [int]$Proc.Id } catch { }
    }
    if ($FreshAppData) {
        $pidFile = Join-Path $FreshAppData 'fa-voice-host.pid'
        if (Test-Path -LiteralPath $pidFile) {
            try {
                $hid = [int]((Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim())
                if ($hid -gt 0) { $ids += $hid }
            }
            catch { }
        }
        try {
            $st = Get-Content -LiteralPath (Join-Path $FreshAppData 'fa-voice-status.json') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue | ConvertFrom-Json
            if ($st.hostPid) { $ids += [int]$st.hostPid }
        }
        catch { }
    }
    foreach ($id in ($ids | Select-Object -Unique)) {
        if ($id -le 0) { continue }
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($p) { return $true }
    }
    return $false
}

function Stop-FreshAgentOrphanVoiceWorkers {
    param(
        [string]$FreshAppData = $(if ($script:FaVoiceWorkerAppData) { $script:FaVoiceWorkerAppData } elseif ($script:FreshAppData) { $script:FreshAppData } else { $null }),
        [int]$KeepHostPid = 0
    )
    # Ne JAMAIS tuer "CyberScribe" par nom : l'app installée Programs\CyberScribe s'appelle ainsi.
    # On ne tue que voice_worker.exe sous FreshWindows*\bin.
    Get-Process -Name 'voice_worker' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $path = [string]$_.Path
            if ($path -and ($path -match '(?i)FreshWindows([^\\]*)\\bin\\voice_worker\.exe$')) {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        }
        catch { }
    }
    if ($FreshAppData) {
        $pidFile = Join-Path $FreshAppData 'fa-voice-host.pid'
        if (Test-Path -LiteralPath $pidFile) {
            try {
                $hid = [int]((Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim())
                if ($hid -gt 0 -and $hid -ne $KeepHostPid) {
                    Stop-Process -Id $hid -Force -ErrorAction SilentlyContinue
                }
            }
            catch { }
            try { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

function Start-FreshAgentVoiceWorkerProcess {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        $AiConfig = $null
    )
    if (Test-FreshAgentVoiceHostAlive -FreshAppData $FreshAppData) {
        Sync-FreshAgentVoiceHostStatus -FreshAppData $FreshAppData
        return $true
    }
    # Evite doubles instances apres un crash agent (micro deja pris).
    Stop-FreshAgentOrphanVoiceWorkers -FreshAppData $FreshAppData

    $exe = Ensure-FreshAgentVoiceWorker -FreshAppData $FreshAppData -AiConfig $AiConfig
    if (-not $exe) { return $false }

    $hostPs1 = Join-Path $FreshAppData 'ai\FreshAgent-VoiceHost.ps1'
    if (-not (Test-Path -LiteralPath $hostPs1)) {
        # Fallback repo / script root for Dev before sync
        $cand = Join-Path (Split-Path $PSScriptRoot -Parent) 'ai\FreshAgent-VoiceHost.ps1'
        if (Test-Path -LiteralPath $cand) {
            New-Item -ItemType Directory -Path (Split-Path $hostPs1 -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $cand -Destination $hostPs1 -Force
        }
    }
    $sttLibDest = Join-Path $FreshAppData 'lib\FreshAgent-SttSettings.ps1'
    if (-not (Test-Path -LiteralPath $sttLibDest)) {
        $sttLibSrc = Join-Path $PSScriptRoot '..\lib\FreshAgent-SttSettings.ps1'
        if (-not (Test-Path -LiteralPath $sttLibSrc)) {
            $sttLibSrc = Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\FreshAgent-SttSettings.ps1'
        }
        if (Test-Path -LiteralPath $sttLibSrc) {
            New-Item -ItemType Directory -Path (Split-Path $sttLibDest -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $sttLibSrc -Destination $sttLibDest -Force
        }
    }
    if (-not (Test-Path -LiteralPath $hostPs1)) {
        Write-FreshAgentVoiceWorkerLog -Message 'FreshAgent-VoiceHost.ps1 absent' -FreshAppData $FreshAppData
        return $false
    }

    $script:FaVoiceWorkerAppData = $FreshAppData
    $lang = 'fr'
    $model = 'small'
    $profile = 'accurate'
    $modelsDir = ''
    if ($AiConfig -and $AiConfig.stt) {
        if ($AiConfig.stt.language) { $lang = [string]$AiConfig.stt.language }
        if ($AiConfig.stt.modelSize) { $model = [string]$AiConfig.stt.modelSize }
        if ($AiConfig.stt.transcriptionProfile) { $profile = [string]$AiConfig.stt.transcriptionProfile }
        if ($AiConfig.stt.modelsDir -and (Test-Path -LiteralPath ([string]$AiConfig.stt.modelsDir))) {
            $modelsDir = [string]$AiConfig.stt.modelsDir
        }
    }
    if (Get-Command Resolve-FreshAgentSttModelSize -ErrorAction SilentlyContinue) {
        $model = Resolve-FreshAgentSttModelSize -Requested $model -ModelsDir $modelsDir
    }
    elseif ($model -eq 'base') { $model = 'small' }

    # Reset status/cmd files
    foreach ($f in @('fa-voice-status.json', 'fa-voice-cmd.jsonl', 'fa-voice-host.pid')) {
        try { Remove-Item -LiteralPath (Join-Path $FreshAppData $f) -Force -ErrorAction SilentlyContinue } catch { }
    }

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    # ProcessStartInfo: HasExited fiable (Start-Process -PassThru peut mentir avec -WindowStyle Hidden).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$hostPs1`" -FreshAppData `"$FreshAppData`" -ExePath `"$exe`" -Language $lang -ModelSize $model -TranscriptionProfile $profile"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $script:FaVoiceWorkerProc = $proc
    $script:FaVoiceWorkerStdin = $null
    $script:FaVoiceWorkerLastActivity = Get-Date
    $script:FaVoiceHostStartedAt = Get-Date
    $script:FaVoiceWorkerReady = $false
    $script:FaVoiceWorkerModelLoaded = $false
    $script:FaVoiceWorkerMicError = $false
    $script:FaVoiceWorkerRecording = $false
    Write-FreshAgentVoiceWorkerLog -Message ("host started pid=$($proc.Id)") -FreshAppData $FreshAppData
    return $true
}

function Stop-FreshAgentVoiceWorkerProcess {
    $app = $(if ($script:FaVoiceWorkerAppData) { $script:FaVoiceWorkerAppData } elseif ($script:FreshAppData) { $script:FreshAppData } else { $null })
    try {
        if ($app) { Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'shutdown' } -FreshAppData $app | Out-Null }
    }
    catch { }
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
    Stop-FreshAgentOrphanVoiceWorkers -FreshAppData $app
}

function Start-FreshAgentVoiceListenSession {
    param(
        [string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }),
        $AiConfig = $null
    )
    if ($script:VoiceListenActive) { return }
    try {
        if (Get-Command Write-WatchLog -ErrorAction SilentlyContinue) {
            Write-WatchLog 'VoiceListenSession: begin'
        }
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
        $script:FaPttHolding = $false
        $script:FaPttRequireRelease = $false
        $script:FaPttKeyWasDown = $false
        $script:FaVoiceTranscribing = $false
        if (Get-Command New-FreshAgentPttMachineState -ErrorAction SilentlyContinue) {
            $script:FaPttMachine = New-FreshAgentPttMachineState
        }
        Remove-Item -LiteralPath (Join-Path $FreshAppData 'fa-stt.paused') -Force -ErrorAction SilentlyContinue

        $ptt = Test-FreshAgentSttPushToTalk -AiConfig $AiConfig
        $script:FaVoicePushToTalk = $ptt
        $hk = Get-FreshAgentPttHotkeyLabel -AiConfig $AiConfig
        $script:FaPttHotkeySpec = Get-FreshAgentPttHotkeySpec -Hotkey $hk

        # Always-on: premier toggle apres ready. PTT: pas d'enregistrement tant que hotkey non maintenu.
        $script:FaVoiceWorkerNeedRearm = $false
        $script:FaVoiceWorkerRearmAfter = $null
        $script:FaVoiceAwaitFirstToggle = -not $ptt

        # Alias auto Legcord/Vesktop -> discord (si detectes)
        try {
            if (Get-Command Ensure-FreshAgentCommonAppAliases -ErrorAction SilentlyContinue) {
                Ensure-FreshAgentCommonAppAliases -FreshAppData $FreshAppData | Out-Null
            }
        }
        catch { }
        if (Get-Command Start-FreshAgentSttPollTimerIfNeeded -ErrorAction SilentlyContinue) {
            Start-FreshAgentSttPollTimerIfNeeded
        }
        if (Get-Command Start-FreshAgentVoiceWatchTimerIfNeeded -ErrorAction SilentlyContinue) {
            Start-FreshAgentVoiceWatchTimerIfNeeded
        }
        if ($ptt) {
            Start-FreshAgentPttTimerIfNeeded
            Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'set_ptt'; enabled = $true } -FreshAppData $FreshAppData | Out-Null
        }
        else {
            Stop-FreshAgentPttTimer
            Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'set_ptt'; enabled = $false } -FreshAppData $FreshAppData | Out-Null
        }
        if ($script:MiAiListenItem) { $script:MiAiListenItem.Text = 'Ecoute : ON (clic = OFF)' }
        if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
            if ($ptt) {
                Show-FreshAgentUserNotice -Title 'Ecoute' -Text ("PTT actif - maintenez $hk pour parler.") -Level Info
            }
            else {
                Show-FreshAgentUserNotice -Title 'Ecoute' -Text 'Toujours actif - parlez pour une commande.' -Level Info
            }
        }
        if (Get-Command Write-WatchLog -ErrorAction SilentlyContinue) {
            Write-WatchLog ("VoiceListenSession: active ptt={0} hotkey={1}" -f $ptt, $hk)
        }
        # Pas de TTS a l'activation: evite feedback micro -> STT des le demarrage.
    }
    catch {
        $script:VoiceListenActive = $false
        $script:VoiceAlwaysOn = $false
        try { Stop-FreshAgentVoiceWorkerProcess } catch { }
        if (Get-Command Write-WatchLog -ErrorAction SilentlyContinue) {
            Write-WatchLog ("VoiceListenSession FAIL: {0}" -f $_.Exception.ToString())
        }
        if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
            Show-FreshAgentUserNotice -Title 'Ecoute' -Text $_.Exception.Message -Level Error
        }
    }
}

function Restart-FreshAgentVoiceListenForConfig {
    param(
        [string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }),
        $AiConfig = $null
    )
    if (-not $script:VoiceListenActive) { return }
    try { Stop-FreshAgentVoiceListenSession } catch { }
    Start-Sleep -Milliseconds 250
    Start-FreshAgentVoiceListenSession -FreshAppData $FreshAppData -AiConfig $AiConfig
}

function Stop-FreshAgentVoiceListenSession {
    $script:VoiceListenActive = $false
    $script:VoiceAlwaysOn = $false
    $script:FaVoiceWorkerNeedRearm = $false
    $script:FaPttHolding = $false
    $script:FaPttRequireRelease = $false
    $script:FaPttKeyWasDown = $false
    $script:FaVoiceTranscribing = $false
    $script:FaPttMachine = $null
    $script:FaVoiceAwaitFirstToggle = $false
    Stop-FreshAgentPttTimer
    if ($script:FaVoiceWorkerRecording) {
        if (Get-Command Send-FreshAgentVoiceRecordStop -ErrorAction SilentlyContinue) {
            Send-FreshAgentVoiceRecordStop | Out-Null
        }
        else {
            Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'toggle' } | Out-Null
        }
        Start-Sleep -Milliseconds 100
    }
    Stop-FreshAgentVoiceWorkerProcess
    if ($script:MiAiListenItem) { $script:MiAiListenItem.Text = 'Ecoute : OFF' }
    if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
        Show-FreshAgentUserNotice -Title 'Ecoute' -Text 'Coupee.' -Level Info
    }
}

function Invoke-FreshAgentPttTick {
    param(
        [string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot })
    )
    if (-not $script:VoiceListenActive) { return }
    if (-not $script:FaVoicePushToTalk) { return }
    if (Test-FreshAgentVoiceListenPaused -FreshAppData $FreshAppData) { return }
    Sync-FreshAgentVoiceHostStatus -FreshAppData $FreshAppData
    if (-not ($script:FaVoiceWorkerReady -or $script:FaVoiceWorkerModelLoaded)) { return }
    if (-not $script:FaPttHotkeySpec) {
        $script:FaPttHotkeySpec = Get-FreshAgentPttHotkeySpec -Hotkey (Get-FreshAgentPttHotkeyLabel)
    }
    if (-not $script:FaPttMachine -and (Get-Command New-FreshAgentPttMachineState -ErrorAction SilentlyContinue)) {
        $script:FaPttMachine = New-FreshAgentPttMachineState
    }

    $down = Test-FreshAgentPttHotkeyDown -Spec $script:FaPttHotkeySpec
    if ($script:FaPttMachine -and (Get-Command Update-FreshAgentPttMachine -ErrorAction SilentlyContinue)) {
        $step = Update-FreshAgentPttMachine -State $script:FaPttMachine -KeyDown $down `
            -Recording ([bool]$script:FaVoiceWorkerRecording) -Transcribing ([bool]$script:FaVoiceTranscribing)
        $script:FaPttMachine = $step.State
        $script:FaPttHolding = [bool]$script:FaPttMachine.Holding
        $script:FaPttRequireRelease = [bool]$script:FaPttMachine.RequireRelease
        foreach ($act in @($step.Actions)) {
            if ($act -eq 'start') {
                Send-FreshAgentVoiceRecordStart -FreshAppData $FreshAppData | Out-Null
                Write-FreshAgentVoiceWorkerLog -Message 'ptt start' -FreshAppData $FreshAppData
            }
            elseif ($act -eq 'stop') {
                Send-FreshAgentVoiceRecordStop -FreshAppData $FreshAppData | Out-Null
                Write-FreshAgentVoiceWorkerLog -Message 'ptt stop' -FreshAppData $FreshAppData
            }
        }
        return
    }

    # Fallback legacy (sans lib STT)
    $wasDown = [bool]$script:FaPttKeyWasDown
    $script:FaPttKeyWasDown = $down
    if ($script:FaVoiceTranscribing) { return }
    if ($script:FaPttRequireRelease) {
        if (-not $down) { $script:FaPttRequireRelease = $false }
        return
    }
    if ($down -and -not $wasDown -and -not $script:FaVoiceWorkerRecording) {
        $script:FaPttHolding = $true
        Send-FreshAgentVoiceRecordStart -FreshAppData $FreshAppData | Out-Null
        Write-FreshAgentVoiceWorkerLog -Message 'ptt start' -FreshAppData $FreshAppData
    }
    elseif (-not $down -and $wasDown -and $script:FaVoiceWorkerRecording) {
        $script:FaPttHolding = $false
        Send-FreshAgentVoiceRecordStop -FreshAppData $FreshAppData | Out-Null
        Write-FreshAgentVoiceWorkerLog -Message 'ptt stop' -FreshAppData $FreshAppData
    }
}

function Start-FreshAgentPttTimerIfNeeded {
    if ($script:FaPttTimer) { return }
    $script:FaPttTimer = New-Object System.Windows.Forms.Timer
    $script:FaPttTimer.Interval = 100
    $script:FaPttTimer.Add_Tick({
            try { Invoke-FreshAgentPttTick } catch { }
        })
    $script:FaPttTimer.Start()
}

function Stop-FreshAgentPttTimer {
    if (-not $script:FaPttTimer) { return }
    try { $script:FaPttTimer.Stop() } catch { }
    try { $script:FaPttTimer.Dispose() } catch { }
    $script:FaPttTimer = $null
}

function Invoke-FreshAgentVoiceWatchTick {
    param(
        [string]$FreshAppData = $(if ($script:FreshAppData) { $script:FreshAppData } else { Get-FreshAgentAppDataRoot }),
        $AiConfig = $null
    )
    if (-not $script:VoiceListenActive) { return }
    Sync-FreshAgentVoiceHostStatus -FreshAppData $FreshAppData
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

    # Host mort: relancer le host (ne pas couper la session ecoute)
    $hostAlive = Test-FreshAgentVoiceHostAlive -FreshAppData $FreshAppData
    if (-not $hostAlive) {
        $now = Get-Date
        # Grace apres demarrage: charge modele Whisper peut prendre >10s
        if ($script:FaVoiceHostStartedAt -and (($now - [datetime]$script:FaVoiceHostStartedAt).TotalSeconds -lt 25)) {
            return
        }
        if ($script:FaVoiceHostRestartAt -and (($now - [datetime]$script:FaVoiceHostRestartAt).TotalSeconds -lt 15)) {
            return
        }
        $script:FaVoiceHostRestartAt = $now
        Write-FreshAgentVoiceWorkerLog -Message 'host exited - restart' -FreshAppData $FreshAppData
        $script:FaVoiceWorkerProc = $null
        $ok = Start-FreshAgentVoiceWorkerProcess -FreshAppData $FreshAppData -AiConfig $AiConfig
        if (-not $ok) {
            Stop-FreshAgentVoiceListenSession
            if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
                Show-FreshAgentUserNotice -Title 'Ecoute' -Text 'Coupee (host vocal arrete).' -Level Warning
            }
            return
        }
        $script:FaVoiceAwaitFirstToggle = -not [bool]$script:FaVoicePushToTalk
        $script:FaPttHolding = $false
        $script:FaPttRequireRelease = $false
        $script:FaVoiceListenStartedAt = Get-Date
        if ($script:FaVoicePushToTalk) { Start-FreshAgentPttTimerIfNeeded }
        return
    }

    # Pendant TTS / pause: le host reporte l'auto-rearm.
    if (Test-FreshAgentVoiceListenPaused -FreshAppData $FreshAppData) {
        return
    }

    # PTT: enregistrement pilote par hotkey (timer dedie).
    if ($script:FaVoicePushToTalk) {
        $down = $false
        if ($script:FaPttHotkeySpec) {
            $down = Test-FreshAgentPttHotkeyDown -Spec $script:FaPttHotkeySpec
        }
        if ($script:FaPttMachine -and (Get-Command Sync-FreshAgentPttMachineAfterRecording -ErrorAction SilentlyContinue)) {
            $script:FaPttMachine = Sync-FreshAgentPttMachineAfterRecording -State $script:FaPttMachine `
                -KeyDown $down -Recording ([bool]$script:FaVoiceWorkerRecording)
            $script:FaPttHolding = [bool]$script:FaPttMachine.Holding
            $script:FaPttRequireRelease = [bool]$script:FaPttMachine.RequireRelease
        }
        elseif (-not $script:FaVoiceWorkerRecording -and $script:FaPttHolding) {
            $script:FaPttRequireRelease = $true
            $script:FaPttHolding = $false
        }
        return
    }

    # Un seul premier toggle apres ready/model (ensuite le host auto-rearme seul).
    if ($script:FaVoiceAwaitFirstToggle) {
        Sync-FreshAgentVoiceHostStatus -FreshAppData $FreshAppData
        if ($script:FaVoiceWorkerReady -or $script:FaVoiceWorkerModelLoaded) {
            $script:FaVoiceAwaitFirstToggle = $false
            Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'toggle' } -FreshAppData $FreshAppData | Out-Null
            Write-FreshAgentVoiceWorkerLog -Message 'first toggle (ready)' -FreshAppData $FreshAppData
        }
        else {
            # Timeout 12s: tenter quand meme
            $started = $script:FaVoiceListenStartedAt
            if ($started -and (((Get-Date) - [datetime]$started).TotalSeconds -ge 12)) {
                $script:FaVoiceAwaitFirstToggle = $false
                Send-FreshAgentVoiceWorkerCmd -Payload @{ cmd = 'toggle' } -FreshAppData $FreshAppData | Out-Null
                Write-FreshAgentVoiceWorkerLog -Message 'first toggle (timeout)' -FreshAppData $FreshAppData
            }
        }
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
