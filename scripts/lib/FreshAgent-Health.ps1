#Requires -Version 5.1
<#
  Snapshots sante maintenance : CPU/RAM/disque (sans IA/voix).
#>

function Get-FreshAgentHealthHistoryPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'health-history.jsonl'
}

function Get-FreshAgentHealthSnapshot {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $snap = [ordered]@{
        at         = (Get-Date).ToString('o')
        cpuPct     = $null
        ramUsedPct = $null
        ramFreeGb  = $null
        diskFreeGb = $null
        gpuName    = $null
        tempC      = $null
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
