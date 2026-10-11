#Requires -Version 5.1
<#
  Confirmation overlay / voix pour actions sensibles.
#>

function Get-FreshAgentPendingConfirmPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'pending-confirm.json'
}

function Clear-FreshAgentPendingConfirm {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $path = Get-FreshAgentPendingConfirmPath -FreshAppData $FreshAppData
    try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch { }
    $script:FaPendingConfirm = $null
}

function Get-FreshAgentPendingConfirm {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    if ($script:FaPendingConfirm) { return $script:FaPendingConfirm }
    $path = Get-FreshAgentPendingConfirmPath -FreshAppData $FreshAppData
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:FaPendingConfirm = $raw
        return $raw
    }
    catch { return $null }
}

function Set-FreshAgentPendingConfirm {
    param(
        [Parameter(Mandatory)][string]$SkillId,
        [hashtable]$Parameters = @{},
        [string]$Prompt = '',
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main',
        [string]$Source = 'agent'
    )
    $payload = @{
        skillId    = $SkillId
        parameters = $Parameters
        prompt     = $Prompt
        repoRef    = $RepoRef
        source     = $Source
        at         = (Get-Date).ToString('o')
    }
    $path = Get-FreshAgentPendingConfirmPath -FreshAppData $FreshAppData
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
    $script:FaPendingConfirm = $payload
    return $payload
}

function Test-FreshAgentSkillRequiresConfirm {
    param($Skill)
    if (-not $Skill) { return $false }
    try {
        if ($null -ne $Skill.requiresConfirm) { return [bool]$Skill.requiresConfirm }
    }
    catch { }
    $id = [string]$Skill.id
    if ($id -match '^(kill_|stop_|shutdown|restart|sleep|lock|power_|cleanup_|dism_|empty_recycle)') {
        return $true
    }
    return $false
}

function Resolve-FreshAgentConfirmUtterance {
    param([Parameter(Mandatory)][string]$Transcript)
    $n = $Transcript
    if (Get-Command ConvertTo-FreshAgentVoiceNormalized -ErrorAction SilentlyContinue) {
        $n = ConvertTo-FreshAgentVoiceNormalized -Text $Transcript
    }
    else {
        $n = $Transcript.Trim().ToLowerInvariant()
    }
    # Accepte "oui.", "ouais", "yes oui", etc.
    if ($n -match '^(?:oui|ouais|ok|okey|daccord|d''accord|confirme|valide|vas-y|go|yes)(?:\s+(?:oui|ok|confirme|vas-y|go))?$') {
        return 'confirm'
    }
    if ($n -match '^(?:non|annule|annuler|cancel|stop|laisse|nope)(?:\s+(?:non|annule))?$') {
        return 'cancel'
    }
    return $null
}
