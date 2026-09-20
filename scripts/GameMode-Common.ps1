#Requires -Version 5.1
<#
  Logique partagee mode jeu (kill list + protection comm/gaming).
  Charge par Invoke-GameModeKill.ps1 et GameMode-WatchAgent.ps1.
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
            KillNames               = @($json | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            ProtectNames            = @()
            GamingLauncherNames     = @()
            GamingLauncherFamilies  = @{}
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

    $families = @{}
    $launchers = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    if ($json.gaming_launcher_families) {
        foreach ($prop in $json.gaming_launcher_families.PSObject.Properties) {
            $names = @()
            foreach ($n in @($prop.Value)) {
                if ([string]::IsNullOrWhiteSpace($n)) { continue }
                $t = $n.Trim()
                $names += $t
                [void]$launchers.Add($t)
            }
            if ($names.Count -gt 0) {
                $families[$prop.Name] = $names
            }
        }
    }

    if ($json.gaming_launchers) {
        foreach ($n in @($json.gaming_launchers)) {
            if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$launchers.Add($n.Trim()) }
        }
        # Compat ancienne liste plate : une famille par nom si pas de families
        if ($families.Count -eq 0) {
            foreach ($n in $launchers) {
                $families[$n] = @($n)
            }
        }
    }

    return @{
        KillNames              = @($kill)
        ProtectNames           = @($protect)
        GamingLauncherNames    = @($launchers)
        GamingLauncherFamilies = $families
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
                $skipped += "$($p.ProcessName) ($($p.Id)) [protege]"
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

function Test-ProcessNameInLauncherSet {
    param(
        [string]$ProcessName,
        [string[]]$LauncherNames
    )
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $false }
    foreach ($n in $LauncherNames) {
        if ($ProcessName.Equals($n, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-GameModeFamilyHasActiveSession {
    <#
      Session active = enfant (ou petit-enfant) d'un process launcher de la famille
      qui n'est PAS lui-meme un process launcher connu.
    #>
    param(
        [System.Diagnostics.Process[]]$FamilyProcs,
        [string[]]$AllLauncherNames,
        [int]$MinChildRamMb = 80
    )

    if (-not $FamilyProcs -or $FamilyProcs.Count -eq 0) { return $false }

    $familyPids = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($p in $FamilyProcs) { [void]$familyPids.Add($p.Id) }

    $minBytes = [int64]$MinChildRamMb * 1MB
    try {
        $cim = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
    }
    catch {
        return $false
    }

    foreach ($row in $cim) {
        if (-not $row.ParentProcessId) { continue }
        if (-not $familyPids.Contains([int]$row.ParentProcessId)) { continue }
        if ($familyPids.Contains([int]$row.ProcessId)) { continue }

        $childName = [string]$row.Name
        if ($childName -match '\.exe$') { $childName = $childName.Substring(0, $childName.Length - 4) }
        if (Test-ProcessNameInLauncherSet -ProcessName $childName -LauncherNames $AllLauncherNames) {
            continue
        }

        try {
            $child = Get-Process -Id $row.ProcessId -ErrorAction SilentlyContinue
            if ($child -and $child.WorkingSet64 -ge $minBytes) {
                return $true
            }
            # Jeu souvent plein ecran meme avec peu de RAM encore chargee
            if ($child -and $child.MainWindowHandle -ne [IntPtr]::Zero) {
                return $true
            }
        }
        catch { }
    }

    # Fallback : chemin exe sous un dossier jeux connu pour un process hors launchers
    foreach ($row in $cim) {
        $path = [string]$row.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($path -notmatch '(?i)\\(EA Games|Electronic Arts|steamapps\\common|Epic Games|GOG Galaxy|Ubisoft|Riot Games)\\') {
            continue
        }
        $childName = [string]$row.Name
        if ($childName -match '\.exe$') { $childName = $childName.Substring(0, $childName.Length - 4) }
        if (Test-ProcessNameInLauncherSet -ProcessName $childName -LauncherNames $AllLauncherNames) {
            continue
        }
        # Lie a la famille si parent dans famille OU path contient marqueur famille
        if ($familyPids.Contains([int]$row.ParentProcessId)) { return $true }
    }

    return $false
}

function Stop-IdleGamingLaunchers {
    <#
      Heuristique par famille : ne tue une famille idle que si une autre a une
      session jeu active. Sans session claire -> ne tue aucun launcher.
    #>
    param(
        [string[]]$LauncherNames,
        [hashtable]$LauncherFamilies = $null,
        [int]$ExcludePid = $PID
    )

    $empty = @{ Killed = @(); Kept = @(); Skipped = @(); Notes = @() }

    if ($LauncherFamilies -and $LauncherFamilies.Count -gt 0) {
        $families = $LauncherFamilies
    }
    elseif ($LauncherNames -and $LauncherNames.Count -gt 0) {
        $families = @{}
        foreach ($n in $LauncherNames) {
            if (-not [string]::IsNullOrWhiteSpace($n)) { $families[$n] = @($n.Trim()) }
        }
    }
    else {
        return $empty
    }

    $allLauncherNames = @()
    foreach ($key in $families.Keys) {
        foreach ($n in @($families[$key])) {
            if ($n) { $allLauncherNames += $n }
        }
    }

    $familyState = @()
    foreach ($famName in ($families.Keys | Sort-Object)) {
        $names = @($families[$famName])
        $procs = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
        foreach ($name in $names) {
            Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Id -ne $ExcludePid) { $procs.Add($_) }
            }
        }
        if ($procs.Count -eq 0) { continue }

        $score = 0.0
        foreach ($p in $procs) {
            $score += [double]$p.WorkingSet64 + ([double]$p.CPU * 2MB)
        }
        $hasSession = Test-GameModeFamilyHasActiveSession -FamilyProcs $procs.ToArray() `
            -AllLauncherNames $allLauncherNames

        $familyState += [pscustomobject]@{
            Name       = $famName
            Procs      = $procs.ToArray()
            Score      = $score
            HasSession = $hasSession
        }
    }

    if ($familyState.Count -eq 0) {
        return $empty
    }

    $activeFamilies = @($familyState | Where-Object { $_.HasSession })
    $kept = @()
    $killed = @()
    $skipped = @()
    $notes = @()

    if ($activeFamilies.Count -eq 0) {
        foreach ($f in $familyState) {
            $kept += ("{0} ({1} proc) [conserve - aucune session jeu claire]" -f $f.Name, $f.Procs.Count)
        }
        $notes += 'Aucune session jeu detectee : aucun launcher tue.'
        return @{ Killed = $killed; Kept = $kept; Skipped = $skipped; Notes = $notes }
    }

    foreach ($f in $familyState) {
        if ($f.HasSession) {
            $kept += ("{0} ({1} proc) [session active]" -f $f.Name, $f.Procs.Count)
            continue
        }

        # Famille idle alors qu'une autre a une session -> kill
        foreach ($p in $f.Procs) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                $killed += "$($p.ProcessName) ($($p.Id)) [$($f.Name)]"
            }
            catch {
                $skipped += "$($p.ProcessName) ($($p.Id)) [$($f.Name)]"
            }
        }
        $notes += ("Famille {0} idle tuee (session active ailleurs)." -f $f.Name)
    }

    return @{ Killed = $killed; Kept = $kept; Skipped = $skipped; Notes = $notes }
}

function Ensure-UltimatePerformanceActive {
    Write-Host "  -> Ultimate Performance (power plan)" -ForegroundColor Gray
    try {
        $list = powercfg /list 2>&1 | Out-String
        $active = [regex]::Match($list, '(?i)\*\s*([A-Fa-f0-9-]{36}).*Ultimate Performance')
        if ($active.Success) {
            Write-Host "    Plan Ultimate deja actif." -ForegroundColor DarkGray
            return $true
        }
        $existing = [regex]::Match($list, '(?i)([A-Fa-f0-9-]{36}).*Ultimate Performance')
        if ($existing.Success) {
            powercfg /setactive $existing.Groups[1].Value | Out-Null
            Write-Host "    Plan Ultimate active." -ForegroundColor DarkGray
            return $true
        }
        $schemeGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        $dup = powercfg /duplicatescheme $schemeGuid 2>&1 | Out-String
        $match = [regex]::Match($dup, '[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}')
        if ($match.Success) {
            powercfg /setactive $match.Value | Out-Null
            Write-Host "    Plan Ultimate cree et active." -ForegroundColor DarkGray
            return $true
        }
        Write-Host "    Impossible d'activer Ultimate Performance." -ForegroundColor DarkYellow
        return $false
    }
    catch {
        Write-Host "    Ultimate Performance ignore : $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $false
    }
}

function Start-FreshWindowsElevated {
    param(
        [string]$SilentMode = '',
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )

    $fresh = Join-Path $env:LOCALAPPDATA 'FreshWindows'
    $stub = Join-Path $fresh 'Launch-FreshWindows.ps1'
    if (-not (Test-Path -LiteralPath $stub)) {
        throw "Stub Fresh Windows introuvable. Menu Fresh Windows → 10 (mode jeu / raccourcis)."
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
    param([string]$WorkingDirectory = '')

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = Join-Path $env:LOCALAPPDATA 'FreshWindows'
    }

    if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
        New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
    }

    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $conhost = "$env:SystemRoot\System32\conhost.exe"

    $wt = $null
    try {
        $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source) { $wt = [string]$cmd.Source }
    } catch { }
    if (-not $wt) {
        $storeWt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
        if (Test-Path -LiteralPath $storeWt) { $wt = $storeWt }
    }

    if ($wt) {
        Start-Process -FilePath $wt -ArgumentList @(
            '-d', $WorkingDirectory,
            '--', $psExe, '-NoProfile', '-NoExit'
        )
        return
    }

    if (Test-Path -LiteralPath $conhost) {
        Start-Process -FilePath $conhost -ArgumentList @(
            $psExe, '-NoProfile', '-NoExit'
        ) -WorkingDirectory $WorkingDirectory
        return
    }

    Start-Process -FilePath $psExe -WorkingDirectory $WorkingDirectory -ArgumentList @('-NoProfile', '-NoExit')
}
