#Requires -Version 5.1
<#
  Chargement configs Fresh Agent (repo GitHub + override LocalAppData).
#>

function Get-FreshAgentAppDataRoot {
    return Join-Path $env:LOCALAPPDATA 'FreshWindows'
}

function Set-FreshScriptUtf8Bom {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $text = $utf8NoBom.GetString($bytes, 3, $bytes.Length - 3)
        }
        else {
            $text = $utf8NoBom.GetString($bytes)
        }
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($Path, $text, $utf8Bom)
    }
    catch { }
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

function Get-FreshAgentUserProtectedFileNames {
    <#
      Fichiers locaux jamais supprimes par le sync repo (overrides / etat).
    #>
    return @(
        'agent-ai.user.json',
        'skills-apps.user.json',
        'skills-web.user.json',
        'inventory.json',
        'game-session.state.json',
        'ai-history.jsonl',
        'ai-prompt.pending.txt'
    )
}

function Get-FreshAgentRegistryFromRepo {
    param([string]$RepoRawRoot)
    $url = "$RepoRawRoot/configs/skills/registry.json"
    return Invoke-FreshAgentRestJson -Url $url
}

function Get-FreshAgentRepoConfigSyncList {
    param(
        [string]$RepoRawRoot,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @(
            'configs/agent-ai.json',
            'configs/skills-apps.json',
            'configs/skills-web.json',
            'configs/skills/registry.json',
            'configs/agent-profiles.json',
            'configs/services-allowlist.json'
        )) {
        [void]$paths.Add($p)
    }

    $reg = $null
    $localReg = Join-Path $FreshAppData 'configs\skills\registry.json'
    if (Test-Path -LiteralPath $localReg) {
        try { $reg = Get-Content -LiteralPath $localReg -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if (-not $reg) {
        $reg = Get-FreshAgentRegistryFromRepo -RepoRawRoot $RepoRawRoot
    }
    if ($reg -and $reg.skills) {
        foreach ($entry in @($reg.skills)) {
            if (-not $entry.file) { continue }
            [void]$paths.Add('configs/skills/' + ($entry.file -replace '\\', '/'))
        }
    }
    return @($paths)
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
        'ai/FreshAgent-BackgroundWorker.ps1',
        'ai/Windows-Stt.ps1',
        'ai/FreshAgent-Tts.ps1',
        'lib/FreshAgent-Inventory.ps1',
        'lib/FreshAgent-Rag.ps1',
        'lib/FreshAgent-History.ps1',
        'lib/FreshAgent-Profiles.ps1',
        'lib/FreshAgent-Log.ps1',
        'lib/FreshAgent-Dashboard.ps1'
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
            Set-FreshScriptUtf8Bom -Path $dest
            Write-Host "-> scripts/$rel" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "!! scripts/$rel : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $configPaths = Get-FreshAgentRepoConfigSyncList -RepoRawRoot $RepoRawRoot -FreshAppData $FreshAppData
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

    if (Get-Command Write-FreshAgentLog -ErrorAction SilentlyContinue) {
        Write-FreshAgentLog -Category 'Sync' -Message ("Assets OK ref={0} configs={1} scripts={2}" -f $Ref, $configPaths.Count, $scriptPaths.Count) -FreshAppData $FreshAppData
    }
    return $true
}

function Import-FreshAgentModule {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $rel = $RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    $candidates = [System.Collections.Generic.List[string]]::new()
    [void]$candidates.Add((Join-Path $FreshAppData $rel))

    if ($PSScriptRoot) {
        [void]$candidates.Add((Join-Path $PSScriptRoot $rel))
        $parent = Split-Path $PSScriptRoot -Parent
        if ($parent) {
            [void]$candidates.Add((Join-Path $parent $rel))
        }
        $leaf = Split-Path $PSScriptRoot -Leaf
        if ($leaf -eq 'lib' -and $rel -like 'lib\*') {
            [void]$candidates.Add((Join-Path $PSScriptRoot ($rel -replace '^lib\\', '')))
        }
        if ($leaf -eq 'scripts' -and $rel -like 'lib\*') {
            [void]$candidates.Add((Join-Path $PSScriptRoot ($rel -replace '^lib\\', 'lib\')))
        }
        if ($rel -like 'ai\*') {
            [void]$candidates.Add((Join-Path $FreshAppData ($rel -replace '^ai\\', 'ai\')))
            if ($parent) {
                [void]$candidates.Add((Join-Path $parent ('scripts\' + $rel)))
            }
        }
    }

    foreach ($path in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            if (Get-Command Set-FreshScriptUtf8Bom -ErrorAction SilentlyContinue) {
                Set-FreshScriptUtf8Bom -Path $path
            }
            $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            Get-ChildItem -Path Function: | ForEach-Object { [void]$known.Add($_.Name) }
            . $path
            Get-ChildItem -Path Function: | Where-Object { -not $known.Contains($_.Name) } | ForEach-Object {
                Set-Item -Path ("script:\function:{0}" -f $_.Name) -Value $_.ScriptBlock -Force
            }
            return $true
        }
        catch {
            return $false
        }
    }
    return $false
}

function Ensure-FreshAgentSkillsLoaded {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    if (Get-Command Invoke-FreshAgentSkill -ErrorAction SilentlyContinue) {
        return $true
    }
    if (Get-Command Import-FreshAgentStandardModules -ErrorAction SilentlyContinue) {
        Import-FreshAgentStandardModules -FreshAppData $FreshAppData
    }
    else {
        foreach ($mod in @(
                'lib/FreshAgent-SkillsEngine.ps1',
                'lib/FreshAgent-SkillHandlers.ps1',
                'lib/FreshAgent-GameSession.ps1',
                'lib/FreshAgent-Inventory.ps1'
            )) {
            if (Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue) {
                Import-FreshAgentModule -RelativePath $mod -FreshAppData $FreshAppData | Out-Null
            }
        }
    }
    return [bool](Get-Command Invoke-FreshAgentSkill -ErrorAction SilentlyContinue)
}

function Ensure-FreshAgentAiBridgeLoaded {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    if (Get-Command Invoke-FreshAgentAiTurn -ErrorAction SilentlyContinue) {
        return $true
    }
    if (-not (Ensure-FreshAgentSkillsLoaded -FreshAppData $FreshAppData)) {
        return $false
    }
    foreach ($mod in @(
            'lib/FreshAgent-Inventory.ps1',
            'lib/FreshAgent-Rag.ps1',
            'ai/Ollama-Manager.ps1',
            'ai/FreshAgent-OllamaBridge.ps1'
        )) {
        if (Get-Command Import-FreshAgentModule -ErrorAction SilentlyContinue) {
            Import-FreshAgentModule -RelativePath $mod -FreshAppData $FreshAppData | Out-Null
        }
    }
    return [bool](Get-Command Invoke-FreshAgentAiTurn -ErrorAction SilentlyContinue)
}

function Import-FreshAgentStandardModules {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    foreach ($mod in @(
            'lib/FreshAgent-SkillsEngine.ps1',
            'lib/FreshAgent-SkillHandlers.ps1',
            'lib/FreshAgent-GameSession.ps1',
            'lib/FreshAgent-Inventory.ps1',
            'lib/FreshAgent-Rag.ps1',
            'lib/FreshAgent-History.ps1',
            'lib/FreshAgent-Profiles.ps1',
            'lib/FreshAgent-Log.ps1',
            'lib/FreshAgent-Dashboard.ps1',
            'ai/Ollama-Manager.ps1',
            'ai/FreshAgent-OllamaBridge.ps1',
            'ai/Windows-Stt.ps1',
            'ai/FreshAgent-Tts.ps1'
        )) {
        Import-FreshAgentModule -RelativePath $mod -FreshAppData $FreshAppData | Out-Null
    }
    Ensure-FreshAgentAiBridgeLoaded -FreshAppData $FreshAppData | Out-Null
}
