#Requires -Version 5.1
<#
  Temps creux : suggestions inventaire / demarrage (jamais de kill auto).
  Ollama idle seulement si IA ON et API deja prete (pas de demarrage "en douce").
#>

function Get-FreshAgentIdleSuggestStatePath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return (Join-Path $FreshAppData 'idle-suggest.state.json')
}

function Test-FreshAgentIdleWindow {
    param([int]$IdleSeconds = 300)
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FaIdle {
  [StructLayout(LayoutKind.Sequential)]
  public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")]
  public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
  public static uint GetIdleMs() {
    LASTINPUTINFO lii = new LASTINPUTINFO();
    lii.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(lii);
    GetLastInputInfo(ref lii);
    return (uint)Environment.TickCount - lii.dwTime;
  }
}
"@ -ErrorAction SilentlyContinue
        $ms = [FaIdle]::GetIdleMs()
        return ($ms -ge ($IdleSeconds * 1000))
    }
    catch {
        return $false
    }
}

function Get-FreshAgentIdleSuggestionMessage {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main'
    )
    # Prefer concrete inventory / startup hints over a generic placeholder.
    $invPath = $null
    if (Get-Command Get-FreshAgentInventoryPath -ErrorAction SilentlyContinue) {
        try { $invPath = Get-FreshAgentInventoryPath -FreshAppData $FreshAppData } catch { }
    }
    if (-not $invPath) { $invPath = Join-Path $FreshAppData 'inventory.json' }

    if (-not (Test-Path -LiteralPath $invPath)) {
        return @{
            suggestion = 'refresh_inventory'
            message    = 'Temps creux : inventaire machine absent — rafraichis (Skills / voix).'
        }
    }

    $invAgeHours = 999
    try {
        $invAgeHours = ((Get-Date) - (Get-Item -LiteralPath $invPath).LastWriteTime).TotalHours
    }
    catch { }
    if ($invAgeHours -ge 24) {
        return @{
            suggestion = 'refresh_inventory'
            message    = ('Temps creux : inventaire vieux de {0:N0} h — rafraichis pour des suggestions utiles.' -f $invAgeHours)
        }
    }

    if (Get-Command Get-FreshAgentStartupAudit -ErrorAction SilentlyContinue) {
        try {
            $startup = @(Get-FreshAgentStartupAudit)
            if ($startup.Count -gt 8) {
                return @{
                    suggestion = 'audit_startup'
                    message    = ('Temps creux : {0} entrees au demarrage — audit suggere (aucune action auto).' -f $startup.Count)
                }
            }
        }
        catch { }
    }

    try {
        $inv = Get-Content -LiteralPath $invPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $procCount = 0
        if ($inv.processes) { $procCount = @($inv.processes).Count }
        elseif ($inv.topProcesses) { $procCount = @($inv.topProcesses).Count }
        if ($procCount -gt 0) {
            return @{
                suggestion = 'check_system_health'
                message    = ('Temps creux : inventaire OK ({0} procs) — dis « etat du systeme » pour un check.' -f $procCount)
            }
        }
    }
    catch { }

    return @{
        suggestion = 'check_system_health'
        message    = 'Temps creux : dis « etat du systeme » ou rafraichis l inventaire.'
    }
}

function Receive-FreshAgentIdleAiSuggestion {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $out = Join-Path $FreshAppData 'idle-suggest-ai.txt'
    if (-not (Test-Path -LiteralPath $out)) { return }
    try {
        $text = (Get-Content -LiteralPath $out -Raw -Encoding UTF8).Trim()
        Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
            Show-FreshAgentUserNotice -Title 'Suggestion' -Text $text -Level Info
        }
        if (Get-Command Add-FreshAgentActionLogEntry -ErrorAction SilentlyContinue) {
            Add-FreshAgentActionLogEntry -Action 'idle_suggest_ai' -SkillId 'idle' -Ok $true `
                -Message $text -Source 'idle' -FreshAppData $FreshAppData
        }
    }
    catch { }
}

function Start-FreshAgentIdleAiSuggestion {
    <#
      Phrase Ollama hors thread UI, sans tool calling.
    #>
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main',
        [Parameter(Mandatory)][string]$Prompt
    )
    $dir = Join-Path $FreshAppData 'temp'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $lock = Join-Path $FreshAppData 'idle-suggest-ai.lock'
    if (Test-Path -LiteralPath $lock) {
        try {
            if (((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalMinutes -lt 10) { return }
        }
        catch { return }
    }
    Set-Content -LiteralPath $lock -Value (Get-Date).ToString('o') -Encoding UTF8
    $promptFile = Join-Path $dir 'idle-ai-prompt.txt'
    Set-Content -LiteralPath $promptFile -Value $Prompt -Encoding UTF8
    $runner = Join-Path $dir 'idle-ai-run.ps1'
    $freshEsc = $FreshAppData.Replace("'", "''")
    $repoEsc = $RepoRef.Replace("'", "''")
    $content = @"
`$ErrorActionPreference = 'Stop'
`$fresh = '$freshEsc'
`$repo = '$repoEsc'
`$lock = Join-Path `$fresh 'idle-suggest-ai.lock'
`$out = Join-Path `$fresh 'idle-suggest-ai.txt'
try {
  . (Join-Path `$fresh 'lib\FreshAgent-Config.ps1')
  . (Join-Path `$fresh 'lib\FreshAgent-SkillsEngine.ps1')
  . (Join-Path `$fresh 'ai\Ollama-Manager.ps1')
  . (Join-Path `$fresh 'ai\FreshAgent-OllamaBridge.ps1')
  `$prompt = Get-Content -LiteralPath (Join-Path `$fresh 'temp\idle-ai-prompt.txt') -Raw -Encoding UTF8
  `$cfg = Get-FreshAgentAiConfig -RepoRef `$repo -FreshAppData `$fresh -PreferLocal
  if (-not `$cfg -or -not `$cfg.enabled) { return }
  `$r = Invoke-FreshAgentAiTurn -UserPrompt ([string]`$prompt).Trim() -AiConfig `$cfg -RepoRef `$repo -FreshAppData `$fresh -NoTools
  if (`$r -and `$r.message) {
    Set-Content -LiteralPath `$out -Value ([string]`$r.message).Trim() -Encoding UTF8
  }
}
catch { }
finally {
  Remove-Item -LiteralPath `$lock -Force -ErrorAction SilentlyContinue
}
"@
    Set-Content -LiteralPath $runner -Value $content -Encoding UTF8
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps)) { $ps = 'powershell.exe' }
    Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner) | Out-Null
}

function Invoke-FreshAgentIdleSuggestTick {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main',
        $AiConfig = $null
    )
    Receive-FreshAgentIdleAiSuggestion -FreshAppData $FreshAppData
    if (-not $AiConfig) { return }
    if (-not [bool]$AiConfig.enabled) { return }
    if (-not (Test-FreshAgentIdleWindow -IdleSeconds 600)) { return }

    $statePath = Get-FreshAgentIdleSuggestStatePath -FreshAppData $FreshAppData
    $last = $null
    if (Test-Path -LiteralPath $statePath) {
        try { $last = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if ($last -and $last.at) {
        try {
            if (((Get-Date) - [datetime]$last.at).TotalHours -lt 12) { return }
        }
        catch { }
    }

    $hint = Get-FreshAgentIdleSuggestionMessage -FreshAppData $FreshAppData -RepoRef $RepoRef
    $msg = [string]$hint.message
    if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
        Show-FreshAgentUserNotice -Title 'Idle' -Text $msg -Level Info
    }
    @{
        at         = (Get-Date).ToString('o')
        suggestion = [string]$hint.suggestion
        message    = $msg
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

    if (Get-Command Add-FreshAgentActionLogEntry -ErrorAction SilentlyContinue) {
        Add-FreshAgentActionLogEntry -Action 'idle_suggest' -SkillId ([string]$hint.suggestion) `
            -Ok $true -Message $msg -Source 'idle' -FreshAppData $FreshAppData
    }

    # Pas de demarrage Ollama ici : uniquement si API deja joignable + suggestion courte.
    $base = 'http://127.0.0.1:11434'
    try {
        if ($AiConfig.ollama -and $AiConfig.ollama.baseUrl) { $base = [string]$AiConfig.ollama.baseUrl }
    }
    catch { }
    $ollamaReady = $false
    if (Get-Command Test-OllamaApi -ErrorAction SilentlyContinue) {
        try { $ollamaReady = [bool](Test-OllamaApi -BaseUrl $base -TimeoutSec 1) } catch { }
    }
    if (-not $ollamaReady) { return }
    if (-not (Get-Command Invoke-FreshAgentAiTurn -ErrorAction SilentlyContinue)) { return }
    try {
        $prompt = "Suggestion idle Fresh Agent: $msg. En une phrase, propose une piste (texte seulement, aucune action, ne tue aucun process)."
        Start-FreshAgentIdleAiSuggestion -FreshAppData $FreshAppData -RepoRef $RepoRef -Prompt $prompt
    }
    catch { }
}
