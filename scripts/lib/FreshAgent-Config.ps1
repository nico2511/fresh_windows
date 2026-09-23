#Requires -Version 5.1
<#
  Chargement configs Fresh Agent (repo GitHub + override LocalAppData).
#>

function Get-FreshAgentAppDataRoot {
    return Join-Path $env:LOCALAPPDATA 'FreshWindows'
}

function Get-FreshAgentRepoRawRoot {
    param([string]$RepoRef)
    if (-not $RepoRef) {
        $RepoRef = if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }
    }
    return "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef"
}

function Expand-FreshAgentPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-FreshAgentConfigFilePath {
    param(
        [string]$RelativePath,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $local = Join-Path $FreshAppData $RelativePath
    if (Test-Path -LiteralPath $local) { return $local }

    $repoRoot = $null
    if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\configs'))) {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\configs')).Path
    }
    if ($repoRoot) {
        $repoFile = Join-Path $repoRoot ($RelativePath -replace '^configs/', '')
        if (Test-Path -LiteralPath $repoFile) { return $repoFile }
    }
    return $local
}

function Invoke-FreshAgentRestJson {
    param(
        [string]$Url,
        [int]$TimeoutSec = 30
    )
    try {
        return Invoke-RestMethod -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
    }
    catch {
        return $null
    }
}

function Merge-FreshAgentJsonObject {
    param(
        $Base,
        $Override
    )
    if ($null -eq $Override) { return $Base }
    if ($null -eq $Base) { return $Override }

    if ($Base -is [System.Collections.IDictionary] -or $Base -is [pscustomobject]) {
        if ($Override -isnot [System.Collections.IDictionary] -and $Override -isnot [pscustomobject]) {
            return $Override
        }
        $hash = @{}
        if ($Base -is [System.Collections.IDictionary]) {
            foreach ($key in $Base.Keys) {
                $hash[[string]$key] = $Base[$key]
            }
        }
        else {
            foreach ($prop in $Base.PSObject.Properties) {
                $hash[$prop.Name] = $prop.Value
            }
        }
        foreach ($prop in $Override.PSObject.Properties) {
            $hash[$prop.Name] = Merge-FreshAgentJsonObject -Base $hash[$prop.Name] -Override $prop.Value
        }
        return [pscustomobject]$hash
    }
    return $Override
}

function Get-FreshAgentAiConfig {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
    $defaults = Invoke-FreshAgentRestJson -Url "$raw/configs/agent-ai.json"
    if (-not $defaults) {
        $defaults = @{
            schemaVersion = 1
            enabled       = $false
            ollama        = @{ baseUrl = 'http://127.0.0.1:11434'; defaultModel = 'qwen2.5:3b'; autoStart = $true }
        } | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    }

    $userPath = Join-Path $FreshAppData 'agent-ai.user.json'
    if (Test-Path -LiteralPath $userPath) {
        try {
            $user = Get-Content -LiteralPath $userPath -Raw -Encoding UTF8 | ConvertFrom-Json
            return Merge-FreshAgentJsonObject -Base $defaults -Override $user
        }
        catch { }
    }
    return $defaults
}

function Set-FreshAgentAiUserConfig {
    param(
        [hashtable]$Patch,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $userPath = Join-Path $FreshAppData 'agent-ai.user.json'
    $current = @{}
    if (Test-Path -LiteralPath $userPath) {
        try {
            $current = Get-Content -LiteralPath $userPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch { }
    }
    $merged = Merge-FreshAgentJsonObject -Base $current -Override ($Patch | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    $merged | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $userPath -Encoding UTF8
}

function Get-FreshAgentSkillsAppsConfig {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $local = Join-Path $FreshAppData 'skills-apps.user.json'
    if (Test-Path -LiteralPath $local) {
        return Get-Content -LiteralPath $local -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
    $remote = Invoke-FreshAgentRestJson -Url "$raw/configs/skills-apps.json"
    if ($remote) { return $remote }
    $path = Get-FreshAgentConfigFilePath -RelativePath 'configs/skills-apps.json' -FreshAppData $FreshAppData
    if (Test-Path -LiteralPath $path) {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return @{ apps = @{} }
}

function Get-FreshAgentSkillsWebConfig {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $local = Join-Path $FreshAppData 'skills-web.user.json'
    if (Test-Path -LiteralPath $local) {
        return Get-Content -LiteralPath $local -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
    $remote = Invoke-FreshAgentRestJson -Url "$raw/configs/skills-web.json"
    if ($remote) { return $remote }
    return @{ searchEngines = @{ google = 'https://www.google.com/search?q={query}' } }
}

function Sync-FreshAgentLocalAssets {
    param(
        [string]$FreshAppData,
        [string]$RepoRawRoot,
        [string]$Ref
    )
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null

    $scriptPaths = @(
        'lib/FreshAgent-Config.ps1',
        'lib/FreshAgent-SkillsEngine.ps1',
        'lib/FreshAgent-SkillHandlers.ps1',
        'lib/FreshAgent-GameSession.ps1',
        'ai/Ollama-Manager.ps1',
        'ai/FreshAgent-OllamaBridge.ps1',
        'ai/Windows-Stt.ps1',
        'ai/FreshAgent-Tts.ps1',
        'lib/FreshAgent-Inventory.ps1',
        'lib/FreshAgent-Rag.ps1',
        'lib/FreshAgent-History.ps1',
        'lib/FreshAgent-Profiles.ps1'
    )
    foreach ($rel in $scriptPaths) {
        $dest = Join-Path $FreshAppData ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dir = Split-Path $dest -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $url = "$RepoRawRoot/scripts/$($rel -replace '\\', '/')"
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            Write-Host "-> scripts/$rel" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "!! scripts/$rel : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $configPaths = @(
        'configs/agent-ai.json',
        'configs/skills-apps.json',
        'configs/skills-web.json',
        'configs/skills/registry.json',
        'configs/skills/system/check_system_health.json',
        'configs/skills/system/launch_app.json',
        'configs/skills/system/game_session.json',
        'configs/skills/system/end_game_session.json',
        'configs/skills/browser/open_url.json',
        'configs/skills/browser/browser_search.json',
        'configs/skills/browser/youtube_search.json',
        'configs/skills/system/refresh_inventory.json',
        'configs/skills/system/list_machine_inventory.json',
        'configs/skills/system/refresh_rag_index.json',
        'configs/skills/system/list_services.json',
        'configs/agent-profiles.json',
        'configs/services-allowlist.json'
    )
    foreach ($rel in $configPaths) {
        $dest = Join-Path $FreshAppData ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $dir = Split-Path $dest -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $url = "$RepoRawRoot/$($rel -replace '\\', '/')"
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            Write-Host "-> $rel" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "!! $rel : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Set-Content -LiteralPath (Join-Path $FreshAppData 'agent.ref') -Value $Ref -Encoding UTF8 -NoNewline
    return $true
}

function Import-FreshAgentModule {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $candidates = @(
        (Join-Path $FreshAppData ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar))
    )
    if ($PSScriptRoot) {
        $candidates += Join-Path $PSScriptRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
        $parent = Split-Path $PSScriptRoot -Parent
        if ($parent) {
            $candidates += Join-Path $parent ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
        }
    }
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            . $path
            return $true
        }
    }
    return $false
}
