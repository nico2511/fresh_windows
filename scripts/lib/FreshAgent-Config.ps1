#Requires -Version 5.1
<#
  Chargement configs Fresh Agent (repo GitHub + override LocalAppData).
#>

function Get-FreshAgentAppDataRoot {
    if ($env:FRESH_WIN_APPDATA -and -not [string]::IsNullOrWhiteSpace($env:FRESH_WIN_APPDATA)) {
        return $env:FRESH_WIN_APPDATA.Trim()
    }
    if ($script:FreshAppData -and -not [string]::IsNullOrWhiteSpace([string]$script:FreshAppData)) {
        return [string]$script:FreshAppData
    }
    return Join-Path $env:LOCALAPPDATA 'FreshWindows'
}

function Set-FreshScriptUtf8Bom {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            return
        }
        $needsBom = $false
        foreach ($b in $bytes) {
            if ($b -gt 127) { $needsBom = $true; break }
        }
        # ASCII pur: PS 5.1 le lit deja correctement. Ne pas reecrire (course entre process, dirty en Dev).
        if (-not $needsBom) { return }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $text = $utf8NoBom.GetString($bytes)
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($Path, $text, $utf8Bom)
    }
    catch { }
}

function Get-FreshAgentScriptsStampPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return (Join-Path $FreshAppData 'scripts.stamp')
}

function Write-FreshAgentScriptsStamp {
    <#
      Marque le contenu agent deja synchronise.
      La valeur vient de configs/agent-content.json (epoch) quand il est present.
    #>
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$Epoch = ''
    )
    if ([string]::IsNullOrWhiteSpace($Epoch)) {
        $contentFile = Join-Path $FreshAppData 'configs\agent-content.json'
        if (Test-Path -LiteralPath $contentFile) {
            try {
                $meta = Get-Content -LiteralPath $contentFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($null -ne $meta.epoch) { $Epoch = [string]$meta.epoch }
            }
            catch { }
        }
    }
    if ([string]::IsNullOrWhiteSpace($Epoch)) { return $false }
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    Set-Content -LiteralPath (Get-FreshAgentScriptsStampPath -FreshAppData $FreshAppData) -Value $Epoch.Trim() -Encoding UTF8 -NoNewline
    return $true
}

function Test-FreshAgentContentStampStale {
    <#
      Dev (scripts.ref = local-dev) n'est jamais perime : pas de resync GitHub.
      Sinon un stamp absent, une branche differente, ou un epoch distant different = perime.
      RemoteEpoch vide = hors ligne : ne pas forcer un sync si un stamp local existe.
    #>
    param(
        [string]$StoredRef = '',
        [string]$LocalEpoch = '',
        [string]$RemoteEpoch = '',
        [string]$RepoRef = 'main',
        [switch]$DevMode
    )
    if ($StoredRef -eq 'local-dev') { return $false }
    if ($DevMode -and [string]::IsNullOrWhiteSpace($StoredRef)) { return $false }
    if ([string]::IsNullOrWhiteSpace($StoredRef)) { return $true }
    $refOnly = ($StoredRef -split '\|', 2)[0].Trim()
    if ($refOnly -ne $RepoRef) { return $true }
    if ([string]::IsNullOrWhiteSpace($LocalEpoch)) { return $true }
    if (-not [string]::IsNullOrWhiteSpace($RemoteEpoch)) {
        return ($RemoteEpoch.Trim() -ne $LocalEpoch.Trim())
    }
    return $false
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
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [switch]$PreferLocal
    )
    $defaults = $null
    $localDefaults = Join-Path $FreshAppData 'configs\agent-ai.json'
    if (Test-Path -LiteralPath $localDefaults) {
        try {
            $defaults = Get-Content -LiteralPath $localDefaults -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch { }
    }
    if (-not $defaults -and -not $PreferLocal) {
        $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
        $defaults = Invoke-FreshAgentRestJson -Url "$raw/configs/agent-ai.json" -TimeoutSec 4
    }
    if (-not $defaults) {
        $defaults = @{
            schemaVersion = 2
            enabled       = $false
            ollama        = @{ baseUrl = 'http://127.0.0.1:11434'; defaultModel = 'qwen2.5:3b'; autoStart = $true; pullOnEnable = $true }
            stt           = @{
                provider       = 'voiceWorker'
                listenSeconds  = 20
                culture        = 'fr-FR'
                route          = 'skills'
                minConfidence  = 0.42
                listenMode     = 'pushToTalk'
                pushToTalk     = $true
                pttHotkey      = 'Ctrl+Alt+Space'
            }
            tts           = @{ provider = 'edge' }
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

function Get-FreshAgentSkillsAppsUserPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'skills-apps.user.json'
}

function Get-FreshAgentSkillsAppsDefaults {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $path = Get-FreshAgentConfigFilePath -RelativePath 'configs/skills-apps.json' -FreshAppData $FreshAppData
    if (Test-Path -LiteralPath $path) {
        try { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    if ($RepoRef) {
        $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
        $remote = Invoke-FreshAgentRestJson -Url "$raw/configs/skills-apps.json"
        if ($remote) { return $remote }
    }
    return @{ schemaVersion = 1; apps = @{} }
}

function Get-FreshAgentSkillsAppsConfig {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $defaults = Get-FreshAgentSkillsAppsDefaults -RepoRef $RepoRef -FreshAppData $FreshAppData
    $userPath = Get-FreshAgentSkillsAppsUserPath -FreshAppData $FreshAppData
    if (-not (Test-Path -LiteralPath $userPath)) {
        return $defaults
    }
    try {
        $user = Get-Content -LiteralPath $userPath -Raw -Encoding UTF8 | ConvertFrom-Json
        # Merge apps: user gagne; aliases = union
        $baseApps = @{}
        if ($defaults.apps) {
            foreach ($p in $defaults.apps.PSObject.Properties) { $baseApps[$p.Name] = $p.Value }
        }
        if ($user.apps) {
            foreach ($p in $user.apps.PSObject.Properties) {
                $key = $p.Name
                if (-not $baseApps.ContainsKey($key)) {
                    $baseApps[$key] = $p.Value
                    continue
                }
                $merged = Merge-FreshAgentJsonObject -Base $baseApps[$key] -Override $p.Value
                # Union aliases
                $aliases = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($a in @($baseApps[$key].aliases)) { if ($a) { [void]$aliases.Add([string]$a) } }
                foreach ($a in @($p.Value.aliases)) { if ($a) { [void]$aliases.Add([string]$a) } }
                try {
                    $merged | Add-Member -NotePropertyName aliases -NotePropertyValue @($aliases) -Force
                }
                catch {
                    $merged = [pscustomobject]@{
                        aliases = @($aliases)
                        process = $(if ($merged.process) { $merged.process } elseif ($p.Value.process) { $p.Value.process } else { $null })
                        paths   = $(if ($p.Value.paths) { @($p.Value.paths) } elseif ($merged.paths) { @($merged.paths) } else { @() })
                    }
                }
                $baseApps[$key] = $merged
            }
        }
        return [pscustomobject]@{
            schemaVersion = 1
            apps          = [pscustomobject]$baseApps
        }
    }
    catch {
        return $defaults
    }
}

function Set-FreshAgentAppAlias {
    <#
      Alias utilisateur: "discord" -> Legcord.exe (persiste dans skills-apps.user.json).
    #>
    param(
        [Parameter(Mandatory)][string]$SpokenName,
        [Parameter(Mandatory)][string]$TargetName,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$ExePath = ''
    )
    $spoken = $SpokenName.Trim()
    $target = $TargetName.Trim()
    if (-not $spoken -or -not $target) {
        return @{ ok = $false; message = 'Alias: noms manquants.' }
    }
    $key = ($spoken.ToLowerInvariant() -replace '[^a-z0-9]+', '')
    if (-not $key) { $key = 'app' }

    $exe = $ExePath
    if (-not $exe -and (Get-Command Resolve-FreshAgentSpokenAppName -ErrorAction SilentlyContinue)) {
        $resolved = Resolve-FreshAgentSpokenAppName -Name $target -FreshAppData $FreshAppData
        $hits = @()
        if (Get-Command Find-FreshAgentStartMenuApps -ErrorAction SilentlyContinue) {
            $hits = @(Find-FreshAgentStartMenuApps -Name $resolved | Where-Object { $_.Score -ge 400 })
        }
        if ($hits.Count -eq 0 -and (Get-Command Find-FreshAgentInstalledApps -ErrorAction SilentlyContinue)) {
            $hits = @(Find-FreshAgentInstalledApps -Name $resolved | Where-Object { $_.Score -ge 400 })
        }
        if ($hits.Count -gt 0) {
            $exe = [string]$hits[0].Path
            # .lnk -> keep lnk (Start-Process OK); prefer display name
            $target = [string]$hits[0].Name
        }
    }
    if (-not $exe -and (Get-Command Find-FreshAgentInstalledApps -ErrorAction SilentlyContinue)) {
        $inst = @(Find-FreshAgentInstalledApps -Name $target)
        if ($inst.Count -gt 0) { $exe = [string]$inst[0].Path; $target = [string]$inst[0].Name }
    }

    $userPath = Get-FreshAgentSkillsAppsUserPath -FreshAppData $FreshAppData
    $user = @{ schemaVersion = 1; apps = @{} }
    if (Test-Path -LiteralPath $userPath) {
        try {
            $raw = Get-Content -LiteralPath $userPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $appsHash = @{}
            if ($raw.apps) {
                foreach ($p in $raw.apps.PSObject.Properties) { $appsHash[$p.Name] = $p.Value }
            }
            $user = @{ schemaVersion = 1; apps = $appsHash }
        }
        catch { }
    }

    $aliases = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @($spoken, $target, $key)) {
        if ($a -and -not $aliases.Contains($a)) { $aliases.Add($a) }
    }
    $existing = $null
    if ($user.apps.ContainsKey($key)) { $existing = $user.apps[$key] }
    if ($existing -and $existing.aliases) {
        foreach ($a in @($existing.aliases)) {
            if ($a -and -not $aliases.Contains([string]$a)) { $aliases.Add([string]$a) }
        }
    }
    $paths = @()
    if ($exe) { $paths = @($exe) }
    elseif ($existing -and $existing.paths) { $paths = @($existing.paths) }

    $user.apps[$key] = [pscustomobject]@{
        aliases = @($aliases)
        process = ($target -replace '\s+', '')
        paths   = $paths
        comment = "Alias: dit '$spoken' -> $target"
    }

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    # Convert apps hashtable to object for JSON
    $out = [ordered]@{
        schemaVersion = 1
        apps          = [pscustomobject]$user.apps
    }
    ($out | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $userPath -Encoding UTF8
    # Invalidate caches that might hold old catalog
    $script:FaStartMenuCatalog = $null
    $script:FaInstalledAppCatalog = $null

    $msg = if ($exe) {
        "Alias OK: '$spoken' -> $target ($exe)"
    }
    else {
        "Alias OK: '$spoken' -> $target (resolu au lancement)"
    }
    return @{ ok = $true; message = $msg; key = $key; path = $userPath }
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
            'configs/agent-content.json',
            'configs/skills-apps.json',
            'configs/skills-web.json',
            'configs/skills/registry.json',
            'configs/skills/router/fr-pc.json',
            'configs/agent-profiles.json',
            'configs/services-allowlist.json',
            'configs/appx-bloatware.json'
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
        'ai/FreshAgent-VoiceWorker.ps1',
        'ai/FreshAgent-VoiceHost.ps1',
        'lib/FreshAgent-Inventory.ps1',
        'lib/FreshAgent-Rag.ps1',
        'lib/FreshAgent-History.ps1',
        'lib/FreshAgent-Profiles.ps1',
        'lib/FreshAgent-Log.ps1',
        'lib/FreshAgent-Dashboard.ps1',
        'lib/FreshAgent-Overlay.ps1',
        'lib/FreshAgent-VoiceRouter.ps1',
        'lib/FreshAgent-IdleSuggest.ps1',
        'lib/FreshAgent-AiLifecycle.ps1',
        'lib/FreshAgent-ActionLog.ps1',
        'lib/FreshAgent-Confirm.ps1',
        'lib/FreshAgent-WindowsActions.ps1',
        'lib/FreshAgent-Health.ps1',
        'lib/FreshAgent-Optimize.ps1',
        'lib/FreshWindows-AppxBloatware.ps1',
        'lib/FreshWindows-BackgroundAudit.ps1'
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
    Write-FreshAgentScriptsStamp -FreshAppData $FreshAppData | Out-Null

    if (Get-Command Write-FreshAgentLog -ErrorAction SilentlyContinue) {
        Write-FreshAgentLog -Category 'Sync' -Message ("Assets OK ref={0} configs={1} scripts={2}" -f $Ref, $configPaths.Count, $scriptPaths.Count) -FreshAppData $FreshAppData
    }
    return $true
}

function Import-FreshAgentFileIntoScriptScope {
    param([Parameter(Mandatory)][string]$LiteralPath)
    # Dot depuis une fonction ne survit pas au return. function script: reste dans le script agent.
    $raw = [System.IO.File]::ReadAllText($LiteralPath)
    $raw = [regex]::Replace($raw, '(?m)^(\s*)#Requires[^\r\n]*', '${1}# requires stripped')
    $raw = [regex]::Replace($raw, '(?m)^(\s*)function\s+(?!script:)([A-Za-z_][\w-]*)', '${1}function script:${2}')
    Invoke-Expression $raw
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
            Import-FreshAgentFileIntoScriptScope -LiteralPath $path
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
            'lib/FreshAgent-Overlay.ps1',
            'lib/FreshAgent-VoiceRouter.ps1',
            'lib/FreshAgent-IdleSuggest.ps1',
            'lib/FreshAgent-AiLifecycle.ps1',
            'lib/FreshAgent-ActionLog.ps1',
            'lib/FreshAgent-Confirm.ps1',
            'lib/FreshAgent-WindowsActions.ps1',
            'lib/FreshAgent-Health.ps1',
            'lib/FreshAgent-Optimize.ps1',
            'lib/FreshWindows-AppxBloatware.ps1',
            'lib/FreshWindows-BackgroundAudit.ps1',
            'ai/Ollama-Manager.ps1',
            'ai/FreshAgent-OllamaBridge.ps1',
            'ai/Windows-Stt.ps1',
            'ai/FreshAgent-Tts.ps1',
            'ai/FreshAgent-VoiceWorker.ps1'
        )) {
        Import-FreshAgentModule -RelativePath $mod -FreshAppData $FreshAppData | Out-Null
    }
    Ensure-FreshAgentAiBridgeLoaded -FreshAppData $FreshAppData | Out-Null
}
