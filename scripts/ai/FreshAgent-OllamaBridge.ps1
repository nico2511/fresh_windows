#Requires -Version 5.1
<#
  Phase 2 — Tool calling Ollama + registry skills dynamique.
#>

function ConvertTo-FreshAgentParameterHashtable {
    param($Obj)
    if ($null -eq $Obj) { return @{} }
    if ($Obj -is [hashtable]) { return $Obj }
    $h = @{}
    foreach ($p in $Obj.PSObject.Properties) {
        $h[$p.Name] = $p.Value
    }
    return $h
}

function Get-FreshAgentDefaultSystemPrompt {
    return @'
Tu es Fresh Agent sur Windows. Reponds en francais, concis.
Pour toute action systeme (apps, web, YouTube, session jeu, etat machine), appelle UN outil (function) du registry.
Ne invente pas de noms d outils. Si tu ne peux pas agir, explique pourquoi.
'@
}

function Get-FreshAgentAiSystemPrompt {
    param(
        $AiConfig,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $base = if ($AiConfig.systemPrompt -and -not [string]::IsNullOrWhiteSpace([string]$AiConfig.systemPrompt)) {
        [string]$AiConfig.systemPrompt
    }
    else {
        Get-FreshAgentDefaultSystemPrompt
    }

    $includeInv = $false
    if ($AiConfig.rag -and $null -ne $AiConfig.rag.includeInventoryInPrompt) {
        $includeInv = [bool]$AiConfig.rag.includeInventoryInPrompt
    }
    elseif ($AiConfig.rag -and $AiConfig.rag.enabled) {
        $includeInv = $true
    }

    if ($includeInv -and (Get-Command Get-FreshAgentInventoryContextText -ErrorAction SilentlyContinue)) {
        $ctx = Get-FreshAgentInventoryContextText -FreshAppData $FreshAppData
        if ($ctx) {
            $base = "$base`n`n$ctx"
        }
    }
    return $base
}

function Get-FreshAgentAiMaxToolRounds {
    param($AiConfig)
    $n = 4
    if ($AiConfig.ollama -and $null -ne $AiConfig.ollama.toolCallMaxRounds) {
        $n = [int]$AiConfig.ollama.toolCallMaxRounds
    }
    if ($n -lt 1) { $n = 1 }
    if ($n -gt 8) { $n = 8 }
    return $n
}

function Get-FreshAgentAiChatTimeout {
    param($AiConfig)
    $sec = 120
    if ($AiConfig.ollama -and $null -ne $AiConfig.ollama.chatTimeoutSec) {
        $sec = [int]$AiConfig.ollama.chatTimeoutSec
    }
    if ($sec -lt 30) { $sec = 30 }
    return $sec
}

function ConvertTo-OllamaToolCallArgumentsHashtable {
    param($ArgumentsRaw)
    if ($null -eq $ArgumentsRaw) { return @{} }
    if ($ArgumentsRaw -is [hashtable]) { return $ArgumentsRaw }
    $text = [string]$ArgumentsRaw
    if ([string]::IsNullOrWhiteSpace($text)) { return @{} }
    try {
        return ConvertTo-FreshAgentParameterHashtable -Obj ($text | ConvertFrom-Json)
    }
    catch {
        return @{}
    }
}

function Get-FreshAgentSkillRequestFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $trim = $Text.Trim()
    if ($trim.StartsWith('{') -and $trim.EndsWith('}')) {
        try {
            $obj = $trim | ConvertFrom-Json
            $skillId = $null
            if ($obj.skill) { $skillId = [string]$obj.skill }
            elseif ($obj.id) { $skillId = [string]$obj.id }
            elseif ($obj.name) { $skillId = [string]$obj.name }
            if ($skillId) {
                $params = @{}
                if ($obj.parameters) {
                    $params = ConvertTo-FreshAgentParameterHashtable -Obj $obj.parameters
                }
                return @{ SkillId = $skillId; Parameters = $params }
            }
        }
        catch { }
    }
    $match = [regex]::Match($Text, '\{[\s\S]*\}')
    if ($match.Success) {
        return Get-FreshAgentSkillRequestFromText -Text $match.Value
    }
    return $null
}

function Format-FreshAgentSkillResultForTool {
    param($SkillResult)
    if ($SkillResult -is [hashtable]) {
        if ($SkillResult.message) {
            $status = if ($SkillResult.ok) { 'OK' } else { 'ERREUR' }
            return "$status : $($SkillResult.message)"
        }
        return ($SkillResult | ConvertTo-Json -Compress)
    }
    return [string]$SkillResult
}

function Invoke-FreshAgentToolCall {
    param(
        [Parameter(Mandatory)]
        [string]$SkillId,
        [hashtable]$Parameters = @{},
        [string]$RepoRef,
        [string]$FreshAppData
    )
    $result = Invoke-FreshAgentSkill -SkillId $SkillId -Parameters $Parameters -RepoRef $RepoRef -FreshAppData $FreshAppData
    return Format-FreshAgentSkillResultForTool -SkillResult $result
}

function Invoke-FreshAgentAiTurn {
    param(
        [Parameter(Mandatory)]
        [string]$UserPrompt,
        $AiConfig,
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }),
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )

    if (-not $AiConfig -or -not $AiConfig.enabled) {
        return @{ ok = $false; message = 'IA desactivee. Active-la dans le menu Intelligence artificielle.' }
    }

    Ensure-OllamaReady -AiConfig $AiConfig -OnProgress { param($m) } | Out-Null

    $tools = @(Get-FreshAgentAiToolSchema -RepoRef $RepoRef -FreshAppData $FreshAppData)
    if ($tools.Count -lt 1) {
        return @{ ok = $false; message = 'Aucun skill expose pour l IA (registry vide).' }
    }

    $timeout = Get-FreshAgentAiChatTimeout -AiConfig $AiConfig
    $maxRounds = Get-FreshAgentAiMaxToolRounds -AiConfig $AiConfig
    $system = Get-FreshAgentAiSystemPrompt -AiConfig $AiConfig -FreshAppData $FreshAppData

    $userContent = $UserPrompt
    if (Get-Command Get-FreshAgentRagContextText -ErrorAction SilentlyContinue) {
        $rag = Get-FreshAgentRagContextText -UserPrompt $UserPrompt -AiConfig $AiConfig -FreshAppData $FreshAppData -RepoRef $RepoRef
        if ($rag) {
            $userContent = "$UserPrompt`n`n$rag"
        }
    }

    $messages = [System.Collections.ArrayList]@(
        @{ role = 'system'; content = $system },
        @{ role = 'user'; content = $userContent }
    )

    $executedSkills = @()

    for ($round = 0; $round -lt $maxRounds; $round++) {
        $resp = Invoke-OllamaChatCompletion -AiConfig $AiConfig -Messages @($messages) -Tools $tools -TimeoutSec $timeout
        if (-not $resp.ok) {
            return @{ ok = $false; message = $resp.message; skills = $executedSkills }
        }

        $msg = $resp.message
        if (-not $msg) {
            return @{ ok = $false; message = 'Reponse Ollama vide.'; skills = $executedSkills }
        }

        $toolCalls = @()
        if ($msg.tool_calls) { $toolCalls = @($msg.tool_calls) }

        if ($toolCalls.Count -eq 0) {
            $fallback = Get-FreshAgentSkillRequestFromText -Text $msg.content
            if ($fallback -and $round -lt ($maxRounds - 1)) {
                $toolCalls = @(
                    @{
                        function = @{
                            name      = $fallback.SkillId
                            arguments = ($fallback.Parameters | ConvertTo-Json -Compress)
                        }
                    }
                )
            }
            else {
                $text = if ($msg.content) { [string]$msg.content.Trim() } else { 'OK.' }
                return @{ ok = $true; message = $text; skills = $executedSkills }
            }
        }

        $assistantEntry = @{
            role    = 'assistant'
            content = if ($msg.content) { [string]$msg.content } else { '' }
        }
        if ($msg.tool_calls -and @($msg.tool_calls).Count -gt 0) {
            $assistantEntry.tool_calls = $msg.tool_calls
        }
        [void]$messages.Add($assistantEntry)

        foreach ($tc in $toolCalls) {
            $fn = $tc.function
            if (-not $fn) { continue }
            $skillId = [string]$fn.name
            $params = ConvertTo-OllamaToolCallArgumentsHashtable -ArgumentsRaw $fn.arguments
            $executedSkills += $skillId
            $toolOutput = Invoke-FreshAgentToolCall -SkillId $skillId -Parameters $params -RepoRef $RepoRef -FreshAppData $FreshAppData
            [void]$messages.Add(@{
                    role    = 'tool'
                    name    = $skillId
                    content = $toolOutput
                })
        }
    }

    return @{
        ok      = $true
        message = 'Limite de tours outils atteinte. Verifie watch-agent.log ou reessaie.'
        skills  = $executedSkills
    }
}

function Invoke-FreshAgentAiPrompt {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        $AiConfig,
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }),
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    return Invoke-FreshAgentAiTurn -UserPrompt $Prompt -AiConfig $AiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
}
