#Requires -Version 5.1

function Resolve-FreshAgentAppEntry {
    param(
        [string]$Name,
        $AppsConfig
    )
    if (-not $AppsConfig -or -not $AppsConfig.apps) { return $null }
    $key = $Name.Trim().ToLowerInvariant()
    foreach ($prop in $AppsConfig.apps.PSObject.Properties) {
        if ($prop.Name.Equals($key, [StringComparison]::OrdinalIgnoreCase)) {
            return @{ Key = $prop.Name; Entry = $prop.Value }
        }
        foreach ($alias in @($prop.Value.aliases)) {
            if ($alias -and $alias.ToString().ToLowerInvariant() -eq $key) {
                return @{ Key = $prop.Name; Entry = $prop.Value }
            }
        }
    }
    return $null
}

function Start-FreshAgentAppEntry {
    param($Entry)
    foreach ($p in @($Entry.paths)) {
        $expanded = Expand-FreshAgentPath -Path $p
        if (Test-Path -LiteralPath $expanded) {
            $args = @($Entry.launchArgs)
            if ($args -and $args.Count -gt 0) {
                Start-Process -FilePath $expanded -ArgumentList $args
            }
            else {
                Start-Process -FilePath $expanded
            }
            return $expanded
        }
    }
    if ($Entry.process) {
        Start-Process -FilePath $Entry.process
        return $Entry.process
    }
    throw "Application introuvable pour ce alias."
}

function Invoke-SkillCheckSystemHealth {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $totalRam = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    # Win32_OperatingSystem.FreePhysicalMemory est en kilo-octets
    $freeRam = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedPct = if ($totalRam -gt 0) { [math]::Round((($totalRam - $freeRam) / $totalRam) * 100, 1) } else { 0 }
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    $diskFree = if ($disk) { [math]::Round($disk.FreeSpace / 1GB, 1) } else { $null }
    $power = Get-ActivePowerSchemeGuid
    $msg = 'CPU ~{0}% | RAM {1} Go libres / {2} Go ({3}% utilise) | C: {4} Go libres | Plan {5}' -f `
        [math]::Round($cpuLoad), $freeRam, $totalRam, $usedPct, $diskFree, $power
    return @{ ok = $true; message = $msg }
}

function Invoke-SkillLaunchApp {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )
    $apps = Get-FreshAgentSkillsAppsConfig -RepoRef $RepoRef
    $resolved = Resolve-FreshAgentAppEntry -Name $Name -AppsConfig $apps
    if (-not $resolved) {
        return @{ ok = $false; message = "Alias inconnu: $Name" }
    }
    $started = Start-FreshAgentAppEntry -Entry $resolved.Entry
    return @{ ok = $true; message = "Lance: $started" }
}

function Invoke-SkillOpenUrl {
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )
    if ($Url -notmatch '^https?://') {
        $Url = 'https://' + $Url
    }
    Start-Process $Url
    return @{ ok = $true; message = "URL ouverte." }
}

function Invoke-SkillBrowserSearch {
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [string]$Engine = 'google',
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )
    $web = Get-FreshAgentSkillsWebConfig -RepoRef $RepoRef
    $template = $web.searchEngines.$Engine
    if (-not $template) { $template = $web.searchEngines.google }
    if (-not $template) {
        return @{ ok = $false; message = 'Moteur de recherche inconnu.' }
    }
    $encoded = [uri]::EscapeDataString($Query)
    $url = $template -replace '\{query\}', $encoded
    Start-Process $url
    return @{ ok = $true; message = "Recherche: $Query" }
}

function Invoke-SkillYoutubeSearch {
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )
    $web = Get-FreshAgentSkillsWebConfig -RepoRef $RepoRef
    $template = if ($web.youtube.search) { $web.youtube.search } else { 'https://www.youtube.com/results?search_query={query}' }
    $url = $template -replace '\{query\}', [uri]::EscapeDataString($Query)
    Start-Process $url
    return @{ ok = $true; message = "YouTube: $Query" }
}

function Invoke-SkillGameSession {
    param(
        [string]$Launch,
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )
    $fresh = Get-FreshAgentAppDataRoot
    if (Get-FreshAgentGameSessionState -FreshAppData $fresh) {
        return @{ ok = $false; message = 'Session jeu deja active. Utilise Fin session jeu.' }
    }

    $focusSnap = Get-WindowsFocusAssistSnapshot
    $focusNotes = Set-WindowsFocusAssistBestEffort -Enable
    $prevPower = Get-ActivePowerSchemeGuid

    if (Get-Command Ensure-UltimatePerformanceActive -ErrorAction SilentlyContinue) {
        Ensure-UltimatePerformanceActive | Out-Null
    }

    $killNotes = @()
    if (Get-Command Get-GameModeKillConfig -ErrorAction SilentlyContinue) {
        $cfg = Get-GameModeKillConfig
        $result = Stop-GameModeKillListProcesses -KillNames $cfg.KillNames -ProtectNames $cfg.ProtectNames
        $idle = Stop-IdleGamingLaunchers -LauncherNames $cfg.GamingLauncherNames -LauncherFamilies $cfg.GamingLauncherFamilies
        $killNotes += "Fermes: $($result.Killed.Count); launchers idle: $($idle.Killed.Count)"
    }

    $launchMsg = $null
    if ($Launch) {
        $r = Invoke-SkillLaunchApp -Name $Launch -RepoRef $RepoRef
        $launchMsg = $r.message
    }

    $state = [pscustomobject]@{
        startedAt   = (Get-Date).ToString('o')
        focusAssist = $focusSnap
        powerScheme = $prevPower
    }
    Set-FreshAgentGameSessionState -State $state -FreshAppData $fresh

    $msg = ($focusNotes + $killNotes) -join ' '
    if ($launchMsg) { $msg += " $launchMsg" }
    return @{ ok = $true; message = $msg.Trim() }
}

function Invoke-SkillEndGameSession {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $state = Get-FreshAgentGameSessionState -FreshAppData $FreshAppData
    if (-not $state) {
        return @{ ok = $false; message = 'Aucune session jeu enregistree.' }
    }
    $notes = Restore-WindowsFocusAssistSnapshot -Snapshot $state.focusAssist
    if ($state.powerScheme) {
        if (Set-ActivePowerSchemeGuid -Guid $state.powerScheme) {
            $notes += 'Plan alimentation restaure.'
        }
    }
    Clear-FreshAgentGameSessionState -FreshAppData $FreshAppData
    return @{ ok = $true; message = ($notes -join ' ') }
}

function Get-FreshAgentServicesAllowlist {
    param(
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }),
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $local = Join-Path $FreshAppData 'configs\services-allowlist.json'
    if (Test-Path -LiteralPath $local) {
        return Get-Content -LiteralPath $local -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
    $remote = Invoke-FreshAgentRestJson -Url "$raw/configs/services-allowlist.json"
    return $remote
}

function Invoke-SkillListServices {
    param(
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )
    $cfg = Get-FreshAgentServicesAllowlist -RepoRef $RepoRef
    if (-not $cfg -or -not $cfg.services) {
        return @{ ok = $false; message = 'Allowlist services introuvable.' }
    }
    $lines = @()
    foreach ($name in @($cfg.services)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            $lines += ("{0}: {1}" -f $svc.Name, $svc.Status)
        }
        else {
            $lines += ("{0}: absent" -f $name)
        }
    }
    return @{ ok = $true; message = ($lines -join ' | ') }
}
