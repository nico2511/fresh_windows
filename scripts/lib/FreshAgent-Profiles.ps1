#Requires -Version 5.1

function Get-FreshAgentProfilesConfig {
    param(
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }),
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $local = Join-Path $FreshAppData 'configs\agent-profiles.json'
    if (Test-Path -LiteralPath $local) {
        return Get-Content -LiteralPath $local -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
    return Invoke-FreshAgentRestJson -Url "$raw/configs/agent-profiles.json"
}

function Invoke-FreshAgentProfile {
    param(
        [Parameter(Mandatory)]
        [string]$ProfileId,
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    if (Get-Command Ensure-FreshAgentSkillsLoaded -ErrorAction SilentlyContinue) {
        if (-not (Ensure-FreshAgentSkillsLoaded -FreshAppData $FreshAppData)) {
            return @{ ok = $false; message = 'Skills Engine absent. Mettre a jour scripts locaux (lib/FreshAgent-SkillsEngine.ps1).' }
        }
    }
    elseif (-not (Get-Command Invoke-FreshAgentSkill -ErrorAction SilentlyContinue)) {
        return @{ ok = $false; message = 'Invoke-FreshAgentSkill indisponible — sync scripts locaux.' }
    }
    $cfg = Get-FreshAgentProfilesConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
    if (-not $cfg -or -not $cfg.profiles) {
        return @{ ok = $false; message = 'Profils indisponibles.' }
    }
    $profile = $cfg.profiles.$ProfileId
    if (-not $profile) {
        return @{ ok = $false; message = "Profil inconnu: $ProfileId" }
    }
    $notes = @()
    foreach ($skillId in @($profile.skills)) {
        $r = Invoke-FreshAgentSkill -SkillId $skillId -Parameters @{} -RepoRef $RepoRef -FreshAppData $FreshAppData
        $notes += if ($r.message) { [string]$r.message } else { $skillId }
    }
    return @{ ok = $true; message = ($notes -join ' | ') }
}
