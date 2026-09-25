#Requires -Version 5.1
<#
  Temps creux : suggestions d'enrichissement kill-list / apps (jamais de kill auto).
  Fallback Ollama optionnel si enabled.
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

function Invoke-FreshAgentIdleSuggestTick {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main',
        $AiConfig = $null
    )
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

    # Suggestion non destructive : proposer refresh inventaire
    $msg = 'Temps creux : inventaire machine a rafraichir ? (menu Skills)'
    if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
        Show-FreshAgentUserNotice -Title 'Idle' -Text $msg -Level Info
    }
    @{ at = (Get-Date).ToString('o'); suggestion = 'refresh_inventory' } |
        ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

    # Fallback Ollama uniquement si bridge pret et enabled
    if (Get-Command Invoke-FreshAgentAiTurn -ErrorAction SilentlyContinue) {
        try {
            $prompt = 'Liste 3 processus Windows souvent inutiles en jeu (noms courts). Reponds tres court.'
            $null = Invoke-FreshAgentAiTurn -Prompt $prompt -RepoRef $RepoRef -FreshAppData $FreshAppData -AiConfig $AiConfig
        }
        catch { }
    }
}
