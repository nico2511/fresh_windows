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

function ConvertTo-FreshAgentConfirmTimestamp {
    <#
      (Get-Date).ToString('o') n'est pas castable en [datetime] sous Windows PowerShell 5.1
      (culture courante). DateTimeOffset garde le decalage, donc l'age reste juste.
    #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetimeoffset]) { return [datetimeoffset]$Value }
    $styles = [Globalization.DateTimeStyles]::RoundtripKind -bor [Globalization.DateTimeStyles]::AllowWhiteSpaces
    $culture = [Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [datetime]) {
        return [datetimeoffset]([datetime]$Value)
    }
    $s = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    # Pas de TryParse+[ref] : le cast PSReference echoue souvent en Windows PowerShell 5.1.
    try {
        return [datetimeoffset]::Parse($s, $culture, $styles)
    }
    catch { }
    foreach ($fmt in @('o', 'yyyy-MM-ddTHH:mm:ss.fffffffK', 'yyyy-MM-ddTHH:mm:ss.fffK', 'yyyy-MM-ddTHH:mm:ssK')) {
        try {
            return [datetimeoffset]::ParseExact($s, $fmt, $culture, $styles)
        }
        catch { }
    }
    return $null
}

function Test-FreshAgentPendingConfirmExpired {
    param(
        $Pending,
        [int]$MaxAgeSeconds = 60
    )
    if (-not $Pending) { return $true }
    $atRaw = $null
    try { $atRaw = $Pending.at } catch { return $true }
    $at = ConvertTo-FreshAgentConfirmTimestamp -Value $atRaw
    if (-not $at) { return $true }
    $age = ([datetimeoffset](Get-Date) - [datetimeoffset]$at).TotalSeconds
    if ($age -lt 0) { return $false }
    return ($age -gt $MaxAgeSeconds)
}

function Get-FreshAgentPendingConfirm {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [int]$MaxAgeSeconds = 60
    )
    $path = Get-FreshAgentPendingConfirmPath -FreshAppData $FreshAppData
    $raw = $null
    if (Test-Path -LiteralPath $path) {
        try { $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $raw = $null }
    }
    elseif ($script:FaPendingConfirm) {
        $raw = $script:FaPendingConfirm
    }
    if (-not $raw) {
        $script:FaPendingConfirm = $null
        return $null
    }
    if (Test-FreshAgentPendingConfirmExpired -Pending $raw -MaxAgeSeconds $MaxAgeSeconds) {
        Clear-FreshAgentPendingConfirm -FreshAppData $FreshAppData
        return $null
    }
    $script:FaPendingConfirm = $raw
    return $raw
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
        if ($null -ne $Skill.requiresConfirm) {
            if (Get-Command ConvertTo-FreshAgentBool -ErrorAction SilentlyContinue) {
                return (ConvertTo-FreshAgentBool -Value $Skill.requiresConfirm -Default $false)
            }
            if ($Skill.requiresConfirm -is [bool]) { return [bool]$Skill.requiresConfirm }
        }
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
