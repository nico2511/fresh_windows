#Requires -Version 5.1
<#
  Surveillance sante v2 : CPU/RAM/disque + historique + kill process verifie.
#>

function Get-FreshAgentHealthHistoryPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'health-history.jsonl'
}

function Get-FreshAgentHealthSnapshot {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $snap = [ordered]@{
        at       = (Get-Date).ToString('o')
        cpuPct   = $null
        ramUsedPct = $null
        ramFreeGb  = $null
        diskFreeGb = $null
        gpuName  = $null
        tempC    = $null
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $total = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        $free = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $snap.ramFreeGb = $free
        if ($total -gt 0) {
            $snap.ramUsedPct = [math]::Round((($total - $free) / $total) * 100, 1)
        }
    }
    catch { }
    # Eviter Start-Job (instable depuis le thread UI WinForms).
    try {
        $avg = (Get-CimInstance Win32_Processor -ErrorAction Stop |
                Measure-Object -Property LoadPercentage -Average).Average
        if ($null -ne $avg) { $snap.cpuPct = [math]::Round([double]$avg) }
    }
    catch { }
    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
        if ($disk) { $snap.diskFreeGb = [math]::Round($disk.FreeSpace / 1GB, 1) }
    }
    catch { }
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gpu -and $gpu.Name) { $snap.gpuName = [string]$gpu.Name }
    }
    catch { }
    # LibreHardwareMonitor optional (named pipe / WMI not required): read LHM report file if present
    try {
        $lhm = Join-Path $FreshAppData 'lhm-temp.txt'
        if (Test-Path -LiteralPath $lhm) {
            $t = (Get-Content -LiteralPath $lhm -Raw -ErrorAction SilentlyContinue).Trim()
            $n = 0.0
            if ([double]::TryParse($t, [ref]$n)) { $snap.tempC = $n }
        }
    }
    catch { }
    return [pscustomobject]$snap
}

function Add-FreshAgentHealthHistory {
    param(
        $Snapshot,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [int]$MaxLines = 288
    )
    if (-not $Snapshot) { return }
    $path = Get-FreshAgentHealthHistoryPath -FreshAppData $FreshAppData
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    ($Snapshot | ConvertTo-Json -Compress) | Add-Content -LiteralPath $path -Encoding UTF8
    try {
        $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
        if ($lines.Count -gt $MaxLines) {
            $lines = $lines[($lines.Count - $MaxLines)..($lines.Count - 1)]
            Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        }
    }
    catch { }
}

function Get-FreshAgentHealthHistory {
    param(
        [int]$Count = 24,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $path = Get-FreshAgentHealthHistoryPath -FreshAppData $FreshAppData
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        $items = @()
        foreach ($line in @(Get-Content -LiteralPath $path -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $items += ($line | ConvertFrom-Json) } catch { }
        }
        return @($items | Select-Object -Last $Count)
    }
    catch { return @() }
}

function Stop-FreshAgentProcessVerified {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$ProcessName = '',
        [string]$MainModulePath = ''
    )
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) {
        return @{ ok = $false; message = "Processus $ProcessId introuvable (deja ferme?)." }
    }
    if ($ProcessName -and $p.ProcessName -ne $ProcessName) {
        return @{
            ok      = $false
            message = "PID recycle: attendu '$ProcessName', trouve '$($p.ProcessName)'."
        }
    }
    if ($MainModulePath) {
        try {
            $path = $p.MainModule.FileName
            if ($path -and -not $path.Equals($MainModulePath, [StringComparison]::OrdinalIgnoreCase)) {
                return @{
                    ok      = $false
                    message = "Module different: attendu autre binaire."
                }
            }
        }
        catch {
            # Access denied on MainModule is ok if name matched
            if ($ProcessName) { }
            else {
                return @{ ok = $false; message = 'Impossible de verifier le module (acces refuse).' }
            }
        }
    }
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        return @{ ok = $true; message = "Ferme: $($p.ProcessName) ($ProcessId)" }
    }
    catch {
        return @{ ok = $false; message = $_.Exception.Message }
    }
}

function Invoke-SkillKillProcess {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [string]$ProcessName = '',
        [string]$MainModulePath = ''
    )
    return Stop-FreshAgentProcessVerified -ProcessId $ProcessId -ProcessName $ProcessName -MainModulePath $MainModulePath
}

function ConvertTo-FreshAgentHealthSpokenAnalysis {
    <#
      Analyse orale FR a partir du snapshot — pas un dump technique.
      Interprete les seuils (charge / memoire / disque / temp) en une phrase naturelle.
    #>
    param($Snapshot)
    if (-not $Snapshot) { return "Je n'ai pas pu lire l'etat du PC." }

    $bits = New-Object System.Collections.Generic.List[string]
    $cpu = $Snapshot.cpuPct
    $ram = $Snapshot.ramUsedPct
    $freeRam = $Snapshot.ramFreeGb
    $disk = $Snapshot.diskFreeGb
    $temp = $Snapshot.tempC

    $verdict = 'Le PC va bien'
    $alerts = New-Object System.Collections.Generic.List[string]

    if ($null -ne $cpu) {
        if ($cpu -ge 85) {
            [void]$alerts.Add('le processeur est tres charge')
            $verdict = 'Le PC est sous pression'
        }
        elseif ($cpu -ge 60) {
            [void]$alerts.Add(("le processeur tourne a environ {0} pour cent" -f $cpu))
        }
        else {
            [void]$bits.Add(("processeur calme a {0} pour cent" -f $cpu))
        }
    }

    if ($null -ne $ram) {
        if ($ram -ge 90) {
            [void]$alerts.Add(("la memoire est presque pleine, seulement {0} Go libres" -f $freeRam))
            $verdict = 'Le PC est sous pression'
        }
        elseif ($ram -ge 75) {
            [void]$alerts.Add(("la memoire est bien remplie a {0} pour cent" -f $ram))
            if ($verdict -eq 'Le PC va bien') { $verdict = 'Le PC tient le coup' }
        }
        else {
            [void]$bits.Add(("memoire comfortable avec {0} Go libres" -f $freeRam))
        }
    }

    if ($null -ne $disk) {
        if ($disk -lt 20) {
            [void]$alerts.Add(("le disque C est presque plein, {0} Go restants" -f $disk))
            $verdict = 'Attention sur le stockage'
        }
        elseif ($disk -lt 50) {
            [void]$bits.Add(("disque C a {0} Go libres" -f $disk))
        }
        else {
            [void]$bits.Add(("disque C aise avec {0} Go libres" -f $disk))
        }
    }

    if ($null -ne $temp) {
        if ($temp -ge 85) {
            [void]$alerts.Add(("temperature elevee a {0} degres" -f [math]::Round([double]$temp)))
            $verdict = 'Le PC chauffe'
        }
        elseif ($temp -ge 70) {
            [void]$bits.Add(("temperature autour de {0} degres" -f [math]::Round([double]$temp)))
        }
    }

    if ($alerts.Count -gt 0) {
        $detail = ($alerts -join ', ')
        return ("{0} : {1}." -f $verdict, $detail)
    }
    if ($bits.Count -gt 0) {
        return ("{0} : {1}." -f $verdict, ($bits -join ', '))
    }
    return 'Le PC repond, mais je manque de mesures precises pour l instant.'
}

function Invoke-SkillCheckHealthV2 {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $snap = Get-FreshAgentHealthSnapshot -FreshAppData $FreshAppData
    Add-FreshAgentHealthHistory -Snapshot $snap -FreshAppData $FreshAppData
    $temp = if ($null -ne $snap.tempC) { "$($snap.tempC) C" } else { 'n/a' }
    $gpu = if ($snap.gpuName) { $snap.gpuName } else { 'n/a' }
    $msg = 'CPU {0}% | RAM {1}% ({2} Go libres) | C: {3} Go | GPU {4} | Temp {5}' -f `
        $snap.cpuPct, $snap.ramUsedPct, $snap.ramFreeGb, $snap.diskFreeGb, $gpu, $temp
    $spoken = ConvertTo-FreshAgentHealthSpokenAnalysis -Snapshot $snap
    return @{ ok = $true; message = $msg; spoken = $spoken; snapshot = $snap }
}
