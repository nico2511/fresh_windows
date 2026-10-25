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

function ConvertTo-FreshAgentBool {
    param(
        $Value,
        [bool]$Default = $false
    )
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [byte] -or $Value -is [decimal] -or $Value -is [double]) {
        return ([int64]$Value) -ne 0
    }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    if ($s -match '^(1|true|yes|oui|on|vrai)$') { return $true }
    if ($s -match '^(0|false|no|non|off|faux)$') { return $false }
    if ($s -eq '') { return $false }
    return $Default
}

function Test-FreshAgentIsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-FreshAgentSkillRequiresAdmin {
    param($Skill)
    if (-not $Skill) { return $false }
    try {
        if ($null -ne $Skill.requiresAdmin) {
            return (ConvertTo-FreshAgentBool -Value $Skill.requiresAdmin -Default $false)
        }
    }
    catch { }
    return $false
}

function Invoke-FreshAgentSkill {
    param(
        [Parameter(Mandatory)]
        [string]$SkillId,
        [hashtable]$Parameters = @{},
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [switch]$SkipConfirm,
        [string]$Source = 'agent'
    )
    $skills = Get-FreshAgentActiveSkills -RepoRef $RepoRef -FreshAppData $FreshAppData
    $skill = $skills | Where-Object { $_.id -eq $SkillId } | Select-Object -First 1
    if (-not $skill) {
        return @{ ok = $false; message = "Skill inconnu: $SkillId" }
    }

    if (Test-FreshAgentSkillRequiresAdmin -Skill $skill) {
        if (-not (Test-FreshAgentIsElevated)) {
            $label = if ($skill.title) { [string]$skill.title } else { $SkillId }
            $msg = "Action refusee: '$label' exige une session administrateur. Ouvre Fresh Windows en admin (Executer en tant qu'administrateur), puis reessaie."
            if (Get-Command Add-FreshAgentActionLogEntry -ErrorAction SilentlyContinue) {
                Add-FreshAgentActionLogEntry -Action 'skill' -SkillId $SkillId -Parameters $Parameters `
                    -Ok $false -Message $msg -Source $Source -FreshAppData $FreshAppData
            }
            return @{
                ok      = $false
                message = $msg
                spoken  = "Il faut les droits administrateur pour cette action."
                skillId = $SkillId
            }
        }
    }

    $needsConfirm = $false
    if (-not $SkipConfirm -and (Get-Command Test-FreshAgentSkillRequiresConfirm -ErrorAction SilentlyContinue)) {
        $needsConfirm = Test-FreshAgentSkillRequiresConfirm -Skill $skill
    }
    if ($SkillId -eq 'remove_preinstalled_apps' -and $needsConfirm) {
        $applyWanted = $false
        if ($Parameters.ContainsKey('Apply')) {
            if (Get-Command ConvertTo-FreshAgentBool -ErrorAction SilentlyContinue) {
                $applyWanted = ConvertTo-FreshAgentBool -Value $Parameters.Apply -Default $false
            }
            elseif ($Parameters.Apply -is [bool]) { $applyWanted = [bool]$Parameters.Apply }
        }
        if (-not $applyWanted) { $needsConfirm = $false }
    }
    if ($needsConfirm) {
        $prompt = if ($skill.confirmPrompt) { [string]$skill.confirmPrompt } elseif ($skill.title) { [string]$skill.title } else { $SkillId }
        if ($SkillId -eq 'close_app' -and (Get-Command Get-FreshAgentCloseAppTargets -ErrorAction SilentlyContinue)) {
            $targetName = ''
            foreach ($key in @('name', 'Name')) {
                if ($Parameters.ContainsKey($key) -and $Parameters[$key]) {
                    $targetName = [string]$Parameters[$key]
                    break
                }
            }
            $preview = Get-FreshAgentCloseAppTargets -Name $targetName -FreshAppData $FreshAppData
            $procList = @($preview.processes)
            if ($procList.Count -eq 0) {
                $miss = if ($preview.message) { [string]$preview.message } else { "Aucun process pour: $targetName" }
                return @{
                    ok      = $false
                    message = $miss
                    spoken  = ("{0} n'est pas ouvert." -f $targetName)
                    skillId = $SkillId
                }
            }
            $names = ($procList | ForEach-Object { '{0} ({1})' -f $_.ProcessName, $_.Id }) -join ', '
            $who = if ($preview.resolvedName) { [string]$preview.resolvedName } else { $targetName }
            $prompt = "Fermer $who : $names"
        }
        if (Get-Command Set-FreshAgentPendingConfirm -ErrorAction SilentlyContinue) {
            Set-FreshAgentPendingConfirm -SkillId $SkillId -Parameters $Parameters -Prompt $prompt `
                -FreshAppData $FreshAppData -RepoRef $RepoRef -Source $Source | Out-Null
        }
        $msg = "Confirmation requise: $prompt. Dis oui ou annule."
        $spokenConfirm = "Je peux $prompt. Dis oui pour confirmer, ou annule."
        if (Get-Command Add-FreshAgentActionLogEntry -ErrorAction SilentlyContinue) {
            Add-FreshAgentActionLogEntry -Action 'confirm_pending' -SkillId $SkillId -Parameters $Parameters `
                -Ok $true -Message $msg -Source $Source -FreshAppData $FreshAppData
        }
        return @{
            ok               = $true
            pendingConfirm   = $true
            message          = $msg
            spoken           = $spokenConfirm
            skillId          = $SkillId
        }
    }

    $handler = $skill.handler
    if ([string]::IsNullOrWhiteSpace($handler) -or -not (Get-Command $handler -ErrorAction SilentlyContinue)) {
        return @{ ok = $false; message = "Handler absent: $handler" }
    }
    try {
        # Inject common params if handler accepts them
        $callParams = @{} + $Parameters
        $meta = (Get-Command $handler).Parameters
        foreach ($key in @($callParams.Keys)) {
            $coerce = $false
            if ($meta.ContainsKey($key)) {
                $pType = $meta[$key].ParameterType
                if ($pType -eq [bool] -or $pType -eq [switch]) { $coerce = $true }
            }
            if (-not $coerce -and $skill.parameters) {
                $spec = $skill.parameters.$key
                if ($spec -and [string]$spec.type -eq 'boolean') { $coerce = $true }
            }
            if ($coerce) {
                $callParams[$key] = ConvertTo-FreshAgentBool -Value $callParams[$key]
            }
        }
        if ($meta.ContainsKey('RepoRef') -and -not $callParams.ContainsKey('RepoRef')) {
            $callParams['RepoRef'] = $RepoRef
        }
        if ($meta.ContainsKey('FreshAppData') -and -not $callParams.ContainsKey('FreshAppData')) {
            $callParams['FreshAppData'] = $FreshAppData
        }
        $result = & $handler @callParams
        if ($null -eq $result) {
            $result = @{ ok = $true; message = 'OK' }
        }
        if (Get-Command Add-FreshAgentActionLogEntry -ErrorAction SilentlyContinue) {
            Add-FreshAgentActionLogEntry -Action 'skill' -SkillId $SkillId -Parameters $Parameters `
                -Ok ([bool]$result.ok) -Message ([string]$result.message) -Source $Source -FreshAppData $FreshAppData
        }
        return $result
    }
    catch {
        if (Get-Command Add-FreshAgentActionLogEntry -ErrorAction SilentlyContinue) {
            Add-FreshAgentActionLogEntry -Action 'skill' -SkillId $SkillId -Parameters $Parameters `
                -Ok $false -Message $_.Exception.Message -Source $Source -FreshAppData $FreshAppData
        }
        return @{ ok = $false; message = $_.Exception.Message }
    }
}

function Complete-FreshAgentPendingConfirm {
    param(
        [ValidateSet('confirm', 'cancel')]
        [string]$Decision,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $pending = $null
    if (Get-Command Get-FreshAgentPendingConfirm -ErrorAction SilentlyContinue) {
        $pending = Get-FreshAgentPendingConfirm -FreshAppData $FreshAppData
    }
    if (-not $pending) {
        return @{ ok = $false; message = 'Aucune action en attente.' }
    }
    if ($Decision -eq 'cancel') {
        if (Get-Command Clear-FreshAgentPendingConfirm -ErrorAction SilentlyContinue) {
            Clear-FreshAgentPendingConfirm -FreshAppData $FreshAppData
        }
        if (Get-Command Add-FreshAgentActionLogEntry -ErrorAction SilentlyContinue) {
            Add-FreshAgentActionLogEntry -Action 'confirm_cancel' -SkillId ([string]$pending.skillId) `
                -Ok $true -Message 'Annule.' -Source 'confirm' -FreshAppData $FreshAppData
        }
        return @{ ok = $true; message = 'Annule.'; cancelled = $true }
    }
    $skillId = [string]$pending.skillId
    $params = @{}
    if ($pending.parameters -is [hashtable]) { $params = $pending.parameters }
    elseif ($pending.parameters) {
        foreach ($p in $pending.parameters.PSObject.Properties) { $params[$p.Name] = $p.Value }
    }
    $repo = if ($pending.repoRef) { [string]$pending.repoRef } else { 'main' }
    if (Get-Command Clear-FreshAgentPendingConfirm -ErrorAction SilentlyContinue) {
        Clear-FreshAgentPendingConfirm -FreshAppData $FreshAppData
    }
    return Invoke-FreshAgentSkill -SkillId $skillId -Parameters $params -RepoRef $repo `
        -FreshAppData $FreshAppData -SkipConfirm -Source 'confirm'
}
