#Requires -Version 5.1
<#
  Bridge Ollama minimal : chat + tools generes depuis le registry skills.
  Phase 2 : tool calling complet ; pour l instant routage texte simple.
#>

function Invoke-FreshAgentAiPrompt {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        $AiConfig,
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )
    if (-not $AiConfig -or -not $AiConfig.enabled) {
        return @{ ok = $false; message = 'IA desactivee (agent-ai.json).' }
    }

    Ensure-OllamaReady -AiConfig $AiConfig -OnProgress { param($m) } | Out-Null
    $tools = Get-FreshAgentAiToolSchema -RepoRef $RepoRef
    $toolHint = ''
    if ($tools -and $tools.Count -gt 0) {
        $ids = ($tools | ForEach-Object { $_.function.name }) -join ', '
        $toolHint = "Skills disponibles: $ids. Reponds en JSON { skill, parameters } si une action est demandee."
    }

    $full = if ($toolHint) { "$toolHint`n`nUtilisateur: $Prompt" } else { $Prompt }
    $text = Invoke-OllamaChat -Prompt $full -AiConfig $AiConfig
    return @{ ok = $true; message = $text }
}
