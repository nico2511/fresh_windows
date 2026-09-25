# Boucle micro hors UI : enregistre 4s, transcrit avec le modele Whisper deja sur disque (CyberScribe).
param(
    [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows')
)
$ErrorActionPreference = 'Continue'
$log = Join-Path $FreshAppData 'watch-agent.log'
function Log([string]$m) {
    try { Add-Content -LiteralPath $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' WHISPER ' + $m) -Encoding UTF8 } catch { }
}

function Find-WhisperModelDir {
    $roots = @(
        'D:\models\cyberscribe_models',
        (Join-Path $env:LOCALAPPDATA 'Programs\CyberScribe\models')
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $bin = Get-ChildItem -LiteralPath $root -Recurse -Filter 'model.bin' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bin) { return $bin.Directory.FullName }
    }
    return $null
}

function Find-Python {
    foreach ($c in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe')
        )) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class FreshMci {
  [DllImport("winmm.dll", CharSet=CharSet.Auto)]
  public static extern int mciSendString(string cmd, StringBuilder ret, int len, IntPtr cb);
}
"@

$model = Find-WhisperModelDir
$python = Find-Python
$pyScript = Join-Path $FreshAppData 'ai\whisper_transcribe.py'
$pending = Join-Path $FreshAppData 'fa-stt-pending.txt'
$pause = Join-Path $FreshAppData 'fa-stt.paused'
$wav = Join-Path $FreshAppData 'fa-stt-chunk.wav'
if (-not $model -or -not $python -or -not (Test-Path -LiteralPath $pyScript)) {
    Log ("loop abort model=[$model] python=[$python]")
    exit 1
}
Log ("loop start model=$model")
while ($true) {
    if (Test-Path -LiteralPath $pause) { Start-Sleep -Milliseconds 400; continue }
    if (Test-Path -LiteralPath $pending) { Start-Sleep -Milliseconds 300; continue }
    try { Remove-Item -LiteralPath $wav -Force -ErrorAction SilentlyContinue } catch { }
    $sb = New-Object System.Text.StringBuilder 256
    [void][FreshMci]::mciSendString('close faMic', $sb, 256, [IntPtr]::Zero)
    $open = [FreshMci]::mciSendString('open new type waveaudio alias faMic', $sb, 256, [IntPtr]::Zero)
    if ($open -ne 0) { Log "mci open $open"; Start-Sleep -Seconds 2; continue }
    [void][FreshMci]::mciSendString('record faMic', $sb, 256, [IntPtr]::Zero)
    Start-Sleep -Seconds 4
    [void][FreshMci]::mciSendString('stop faMic', $sb, 256, [IntPtr]::Zero)
    $save = [FreshMci]::mciSendString("save faMic `"$wav`"", $sb, 256, [IntPtr]::Zero)
    [void][FreshMci]::mciSendString('close faMic', $sb, 256, [IntPtr]::Zero)
    if ($save -ne 0 -or -not (Test-Path -LiteralPath $wav)) { Log "mci save $save"; continue }
    if ((Get-Item -LiteralPath $wav).Length -lt 8000) { continue }
    $out = & $python $pyScript $model $wav 2>> $log
    $text = ([string]$out).Trim()
    if ($text.Length -ge 2) {
        Set-Content -LiteralPath $pending -Value $text -Encoding UTF8
        Log ("text: $text")
    }
}
