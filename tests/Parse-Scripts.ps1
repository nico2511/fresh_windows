$files = @(
    'launcher.ps1',
    'scripts\GameMode-Common.ps1',
    'scripts\Invoke-GameModeKill.ps1',
    'scripts\GameMode-WatchAgent.ps1',
    'scripts\Sync-FreshWindowsAgent.ps1',
    'scripts\Start-FreshAgentDev.ps1',
    'scripts\Stop-FreshAgentDev.ps1',
    'scripts\lib\Launcher-WinUtil.ps1',
    'scripts\lib\Launcher-GpuMenus.ps1',
    'scripts\lib\Launcher-Tasks.ps1',
    'scripts\lib\Launcher-Core.ps1',
    'scripts\lib\FreshAgent-Config.ps1',
    'scripts\lib\FreshAgent-Log.ps1',
    'scripts\lib\FreshAgent-SkillsEngine.ps1',
    'scripts\lib\FreshAgent-SkillHandlers.ps1',
    'scripts\lib\FreshAgent-GameSession.ps1',
    'scripts\lib\FreshAgent-Overlay.ps1',
    'scripts\lib\FreshAgent-VoiceRouter.ps1',
    'scripts\lib\FreshAgent-IdleSuggest.ps1',
    'scripts\lib\FreshAgent-AiLifecycle.ps1',
    'scripts\lib\FreshAgent-Dashboard.ps1',
    'scripts\lib\FreshAgent-ActionLog.ps1',
    'scripts\lib\FreshAgent-Confirm.ps1',
    'scripts\lib\FreshAgent-WindowsActions.ps1',
    'scripts\lib\FreshAgent-Health.ps1',
    'scripts\lib\FreshAgent-Optimize.ps1',
    'scripts\lib\FreshWindows-AppxBloatware.ps1',
    'scripts\ai\Ollama-Manager.ps1',
    'scripts\ai\Windows-Stt.ps1',
    'scripts\ai\FreshAgent-OllamaBridge.ps1',
    'scripts\ai\FreshAgent-Tts.ps1',
    'scripts\ai\FreshAgent-VoiceWorker.ps1',
    'scripts\ai\FreshAgent-VoiceHost.ps1',
    'scripts\ai\FreshAgent-BackgroundWorker.ps1'
)
function Test-FreshPs1Utf8Bom {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $nonAscii = $false
    foreach ($b in $bytes) {
        if ($b -gt 127) { $nonAscii = $true; break }
    }
    # Windows PowerShell 5.1 lit un .ps1 sans BOM dans la page ANSI, pas en UTF-8.
    if ($nonAscii -and -not $hasBom) { return $false }
    return $true
}

$bad = 0
$repoRoot = Split-Path $PSScriptRoot -Parent
Write-Host "=== UTF-8 BOM (PS 5.1) ==="
Get-ChildItem -LiteralPath $repoRoot -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    ForEach-Object {
        $rel = $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
        if (Test-FreshPs1Utf8Bom -Path $_.FullName) {
            Write-Host "OK BOM $rel"
        }
        else {
            Write-Host "FAIL BOM $rel (non-ASCII sans UTF-8 BOM)"
            $bad++
        }
    }

foreach ($f in $files) {
    $errs = $null
    $path = Join-Path $PSScriptRoot $f
    if (-not (Test-Path $path)) { $path = Join-Path (Get-Location) $f }
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        Write-Host "FAIL $f"
        $errs | ForEach-Object { Write-Host $_.Message }
        $bad++
    }
    else {
        Write-Host "OK $f"
    }
}
exit $bad
