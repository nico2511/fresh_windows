#Requires -Version 5.1
<#
  Cycle de vie IA : un seul chemin Enable/Disable.
  IA ON => Ollama autoStart + EnsureModel (pas de fallback modele).
#>

function Enable-FreshAgentAi {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main',
        [scriptblock]$OnEnsureModel = $null
    )
    # Force autoStart + pull quand on active l'IA (pas d'option "IA ON sans Ollama").
    Set-FreshAgentAiUserConfig -Patch @{
        enabled = $true
        ollama  = @{
            autoStart    = $true
            pullOnEnable = $true
        }
    } -FreshAppData $FreshAppData

    $cfg = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData -PreferLocal
    if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
        Show-FreshAgentUserNotice -Title 'IA' -Text 'Activation — demarrage Ollama + modele...' -Level Info
    }

    if ($OnEnsureModel -is [scriptblock]) {
        & $OnEnsureModel
    }
    elseif (Get-Command Start-FreshAgentBackgroundWork -ErrorAction SilentlyContinue) {
        Start-FreshAgentBackgroundWork -Action EnsureModel -BusyTitle 'Fresh Agent IA' -BusyText 'Demarrage Ollama + modele...'
    }

    return $cfg
}

function Disable-FreshAgentAi {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main'
    )
    Set-FreshAgentAiUserConfig -Patch @{ enabled = $false } -FreshAppData $FreshAppData
    $cfg = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData -PreferLocal
    if (Get-Command Show-FreshAgentUserNotice -ErrorAction SilentlyContinue) {
        Show-FreshAgentUserNotice -Title 'IA' -Text 'Desactivee.' -Level Info
    }
    return $cfg
}

function Set-FreshAgentAiEnabled {
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main',
        [scriptblock]$OnEnsureModel = $null
    )
    if ($Enabled) {
        return (Enable-FreshAgentAi -FreshAppData $FreshAppData -RepoRef $RepoRef -OnEnsureModel $OnEnsureModel)
    }
    return (Disable-FreshAgentAi -FreshAppData $FreshAppData -RepoRef $RepoRef)
}
