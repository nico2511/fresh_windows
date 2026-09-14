#Requires -Version 5.1
<#
  Logique partagée mode jeu (kill list + protection comm/gaming).
  Chargé par Invoke-GameModeKill.ps1 et GameMode-WatchAgent.ps1.
#>
param(
    [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
)

$script:GameModeConfigUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/configs/game-mode-kill.json"

function Get-GameModeKillConfig {
    param([string]$ConfigUrl = $script:GameModeConfigUrl)

    $json = Invoke-RestMethod -Uri $ConfigUrl -UseBasicParsing
    if ($json -is [System.Array]) {
        return @{
            KillNames           = @($json | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            ProtectNames        = @()
            GamingLauncherNames = @()
        }
    }

    $kill = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($json.domains) {
        foreach ($prop in $json.domains.PSObject.Properties) {
            foreach ($n in @($prop.Value)) {
                if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$kill.Add($n.Trim()) }
            }
        }
    }

    $protect = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($json.protect) {
        foreach ($prop in $json.protect.PSObject.Properties) {
            foreach ($n in @($prop.Value)) {
                if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$protect.Add($n.Trim()) }
            }
        }
    }

    foreach ($p in $protect) { $kill.Remove($p) | Out-Null }

    $launchers = @()
    if ($json.gaming_launchers) {
        foreach ($n in @($json.gaming_launchers)) {
            if (-not [string]::IsNullOrWhiteSpace($n)) { $launchers += $n.Trim() }
        }
    }

    return @{
        KillNames             = @($kill)
        ProtectNames          = @($protect)
        GamingLauncherNames   = $launchers
    }
}

function Test-GameModeProtectedProcess {
    param(
        [string]$ProcessName,
        [string[]]$ProtectNames
    )
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $false }
    foreach ($p in $ProtectNames) {
        if ($ProcessName.Equals($p, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Stop-GameModeKillListProcesses {
    param(
        [string[]]$KillNames,
        [string[]]$ProtectNames,
        [int]$ExcludePid = $PID
    )

    $killed = @()
    $skipped = @()

    foreach ($name in $KillNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if (Test-GameModeProtectedProcess -ProcessName $name -ProtectNames $ProtectNames) { continue }

        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $ExcludePid }
        foreach ($p in $procs) {
            if (Test-GameModeProtectedProcess -ProcessName $p.ProcessName -ProtectNames $ProtectNames) {
                $skipped += "$($p.ProcessName) ($($p.Id)) [protégé]"
                continue
            }
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                $killed += "$($p.ProcessName) ($($p.Id))"
            }
            catch {
                $skipped += "$($p.ProcessName) ($($p.Id))"
            }
        }
    }

    return @{ Killed = $killed; Skipped = $skipped }
}

function Stop-IdleGamingLaunchers {
    <#
      Plusieurs launchers ouverts : garde celui qui consomme le plus (RAM/CPU),
      ferme les autres (Epic + GOG pendant une session Steam = inutile).
    #>
    param(
        [string[]]$LauncherNames,
        [int]$ExcludePid = $PID
    )

    if (-not $LauncherNames -or $LauncherNames.Count -eq 0) {
        return @{ Killed = @(); Kept = @(); Skipped = @() }
    }

    $running = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $LauncherNames) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Id -ne $ExcludePid) { $running.Add($_) }
        }
    }

    if ($running.Count -le 1) {
        $kept = if ($running.Count -eq 1) { @("$($running[0].ProcessName) ($($running[0].Id))") } else { @() }
        return @{ Killed = @(); Kept = $kept; Skipped = @() }
    }

    $scored = @(
        $running | ForEach-Object {
            $score = [double]$_.WorkingSet64 + ([double]$_.CPU * 2MB)
            [pscustomobject]@{ Proc = $_; Score = $score }
        } | Sort-Object Score -Descending
    )

    $keep = $scored[0].Proc
    $kept = @("$($keep.ProcessName) ($($keep.Id)) [actif]")
    $killed = @()
    $skipped = @()

    foreach ($item in ($scored | Select-Object -Skip 1)) {
        $p = $item.Proc
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            $killed += "$($p.ProcessName) ($($p.Id))"
        }
        catch {
            $skipped += "$($p.ProcessName) ($($p.Id))"
        }
    }

    return @{ Killed = $killed; Kept = $kept; Skipped = $skipped }
}

function Start-FreshWindowsElevated {
    param(
        [string]$SilentMode = '',
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )

    $fresh = Join-Path $env:LOCALAPPDATA 'FreshWindows'
    $stub = Join-Path $fresh 'Launch-FreshWindows.ps1'
    if (-not (Test-Path -LiteralPath $stub)) {
        throw "Stub Fresh Windows introuvable. Menu Fresh Windows → 11 (raccourcis)."
    }

    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$stub`""
    if (-not [string]::IsNullOrWhiteSpace($SilentMode)) {
        $argList += " -SilentMode `"$SilentMode`""
    }

    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Verb RunAs `
        -ArgumentList $argList `
        -WorkingDirectory $fresh
}

function Start-FreshWindowsPowerShell {
    param([string]$WorkingDirectory = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'))

    if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
        New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
    }

    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-NoProfile -NoExit -Command Set-Location -LiteralPath '$WorkingDirectory'" `
        -WorkingDirectory $WorkingDirectory
}
