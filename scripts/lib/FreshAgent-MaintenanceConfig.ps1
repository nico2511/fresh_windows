#Requires -Version 5.1
<#
  Sync maintenance agent (systray) vers %LOCALAPPDATA%\FreshWindows — sans IA/voix.
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
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return }
        $needsBom = $false
        foreach ($b in $bytes) { if ($b -gt 127) { $needsBom = $true; break } }
        if (-not $needsBom) { return }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $text = $utf8NoBom.GetString($bytes)
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($Path, $text, $utf8Bom)
    }
    catch { }
}

function Get-FreshMaintenanceSyncManifest {
    return @{
        Scripts = @(
            'GameMode-Common.ps1',
            'Invoke-GameModeKill.ps1',
            'GameMode-WatchAgent.ps1',
            'Stop-FreshWatchAgent.ps1',
            'Sync-FreshWindowsAgent.ps1',
            'Invoke-FreshWindowsBackgroundAudit.ps1'
        )
        Libs = @(
            'lib/FreshAgent-MaintenanceConfig.ps1',
            'lib/FreshAgent-Log.ps1',
            'lib/FreshAgent-GameSession.ps1',
            'lib/FreshAgent-Optimize.ps1',
            'lib/FreshAgent-Health.ps1',
            'lib/FreshWindows-AppxBloatware.ps1',
            'lib/FreshWindows-BackgroundAudit.ps1'
        )
        Configs = @(
            'configs/game-mode-watch.json',
            'configs/maintenance-content.json'
        )
    }
}

function Sync-FreshMaintenanceLocalAssets {
    param(
        [Parameter(Mandatory)][string]$FreshAppData,
        [Parameter(Mandatory)][string]$RepoRawRoot,
        [string]$Ref = 'main'
    )

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $manifest = Get-FreshMaintenanceSyncManifest

    foreach ($rel in $manifest.Scripts) {
        $dest = Join-Path $FreshAppData (Split-Path $rel -Leaf)
        if ($rel -match '/') { $dest = Join-Path $FreshAppData $rel }
        $url = "$RepoRawRoot/scripts/$rel"
        if ($rel -notmatch '/') { $url = "$RepoRawRoot/scripts/$rel" }
        else {
            $url = "$RepoRawRoot/scripts/$($rel -replace '\\','/')"
        }
        $dest = Join-Path $FreshAppData ([System.IO.Path]::GetFileName($rel))
        if ($rel -like 'lib/*') { continue }
        Invoke-WebRequest -Uri "$RepoRawRoot/scripts/$rel" -OutFile $dest -UseBasicParsing
        Set-FreshScriptUtf8Bom -Path $dest
    }

    foreach ($rel in $manifest.Libs) {
        $dest = Join-Path $FreshAppData $rel
        $dir = Split-Path $dest -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Invoke-WebRequest -Uri "$RepoRawRoot/scripts/$rel" -OutFile $dest -UseBasicParsing
        Set-FreshScriptUtf8Bom -Path $dest
    }

    $cfgDir = Join-Path $FreshAppData 'configs'
    New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
    foreach ($rel in $manifest.Configs) {
        $name = Split-Path $rel -Leaf
        $dest = Join-Path $cfgDir $name
        Invoke-WebRequest -Uri "$RepoRawRoot/$rel" -OutFile $dest -UseBasicParsing
    }

    return $true
}
