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
            KillNames   = @($json | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            ProtectNames = @()
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

    return @{
        KillNames    = @($kill)
        ProtectNames = @($protect)
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
