#Requires -Version 5.1

function Get-FreshAgentSkillsRegistry {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $localReg = Join-Path $FreshAppData 'configs/skills/registry.json'
    if (Test-Path -LiteralPath $localReg) {
        return Get-Content -LiteralPath $localReg -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
    $remote = Invoke-FreshAgentRestJson -Url "$raw/configs/skills/registry.json"
    if ($remote) { return $remote }
    return @{ skills = @() }
}

function Get-FreshAgentSkillDefinition {
    param(
        [string]$SkillFile,
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $local = Join-Path $FreshAppData ('configs/skills/' + $SkillFile)
    if (Test-Path -LiteralPath $local) {
        return Get-Content -LiteralPath $local -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
    $url = "$raw/configs/skills/$($SkillFile -replace '\\', '/')"
    $remote = Invoke-FreshAgentRestJson -Url $url
    return $remote
}

function Get-FreshAgentActiveSkills {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $reg = Get-FreshAgentSkillsRegistry -RepoRef $RepoRef -FreshAppData $FreshAppData
    $list = @()
    foreach ($entry in @($reg.skills)) {
        if (-not $entry.enabled) { continue }
        $def = Get-FreshAgentSkillDefinition -SkillFile $entry.file -RepoRef $RepoRef -FreshAppData $FreshAppData
        if ($def) { $list += $def }
    }
    return $list
}

function Get-FreshAgentAiToolSchema {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $tools = @()
    foreach ($skill in Get-FreshAgentActiveSkills -RepoRef $RepoRef -FreshAppData $FreshAppData) {
        if (-not $skill.ai -or -not $skill.ai.expose) { continue }
        $props = @{}
        if ($skill.parameters) {
            foreach ($p in $skill.parameters.PSObject.Properties) {
                $props[$p.Name] = @{
                    type        = if ($p.Value.type) { $p.Value.type } else { 'string' }
                    description = $p.Value.description
                }
            }
        }
        $required = @()
        if ($skill.parameters) {
            $required = @($skill.parameters.PSObject.Properties | Where-Object { $_.Value.required } | ForEach-Object { $_.Name })
        }
        $tools += @{
            type     = 'function'
            function = @{
                name        = $skill.id
                description = $skill.ai.description
                parameters  = @{
                    type       = 'object'
                    properties = $props
                    required   = $required
                }
            }
        }
    }
    return $tools
}

function Invoke-FreshAgentSkill {
    param(
        [Parameter(Mandatory)]
        [string]$SkillId,
        [hashtable]$Parameters = @{},
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $skills = Get-FreshAgentActiveSkills -RepoRef $RepoRef -FreshAppData $FreshAppData
    $skill = $skills | Where-Object { $_.id -eq $SkillId } | Select-Object -First 1
    if (-not $skill) {
        return @{ ok = $false; message = "Skill inconnu: $SkillId" }
    }
    $handler = $skill.handler
    if ([string]::IsNullOrWhiteSpace($handler) -or -not (Get-Command $handler -ErrorAction SilentlyContinue)) {
        return @{ ok = $false; message = "Handler absent: $handler" }
    }
    try {
        $result = & $handler @Parameters
        if ($null -eq $result) {
            return @{ ok = $true; message = 'OK' }
        }
        return $result
    }
    catch {
        return @{ ok = $false; message = $_.Exception.Message }
    }
}
