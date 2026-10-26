#Requires -Version 5.1
<#
  Optimisation : nettoyage, audit demarrage/services, restore point, rapport hebdo.
#>

function Get-FreshAgentProcessMemoryMb {
    try {
        $p = [System.Diagnostics.Process]::GetCurrentProcess()
        return @{
            wsMb      = [math]::Round($p.WorkingSet64 / 1MB, 1)
            privateMb = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
        }
    }
    catch {
        return @{ wsMb = 0; privateMb = 0 }
    }
}

function Invoke-FreshAgentWorkingSetTrim {
    try {
        if (-not ('FreshAgentMemNative' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FreshAgentMemNative {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool SetProcessWorkingSetSize(IntPtr hProcess, IntPtr min, IntPtr max);
    [DllImport("psapi.dll", SetLastError=true)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
'@
        }
        $h = [System.Diagnostics.Process]::GetCurrentProcess().Handle
        $ok1 = [FreshAgentMemNative]::SetProcessWorkingSetSize($h, [IntPtr]::Zero, [IntPtr]::Zero)
        $ok2 = [FreshAgentMemNative]::EmptyWorkingSet($h)
        return @{ ok = ($ok1 -or $ok2); trimmed = $true }
    }
    catch {
        return @{ ok = $false; trimmed = $false; message = $_.Exception.Message }
    }
}

function New-FreshAgentRestorePoint {
    param([string]$Description = 'Fresh Agent')
    $elevated = $false
    try {
        if (Get-Command Test-FreshAgentIsElevated -ErrorAction SilentlyContinue) {
            $elevated = [bool](Test-FreshAgentIsElevated)
        }
        else {
            $id = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($id)
            $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
    }
    catch { $elevated = $false }
    if (-not $elevated) {
        return @{ ok = $false; message = "Point de restauration ignore: session non administrateur." }
    }
    try {
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        return @{ ok = $true; message = "Point de restauration: $Description" }
    }
    catch {
        return @{ ok = $false; message = "Restore point: $($_.Exception.Message)" }
    }
}

function Invoke-FreshAgentCleanup {
    param(
        [switch]$Temp,
        [switch]$RecycleBin,
        [switch]$WuCache,
        [switch]$Dism,
        [switch]$CreateRestorePoint
    )
    $notes = [System.Collections.ArrayList]@()
    if ($CreateRestorePoint) {
        $rp = New-FreshAgentRestorePoint -Description 'Fresh Agent cleanup'
        [void]$notes.Add($rp.message)
    }
    if ($Temp) {
        foreach ($dir in @($env:TEMP, (Join-Path $env:WINDIR 'Temp'))) {
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            try {
                Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '^FreshWindows' } |
                    ForEach-Object {
                        try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { }
                    }
                [void]$notes.Add("Temp nettoye: $dir")
            }
            catch {
                [void]$notes.Add("Temp echoue: $dir")
            }
        }
    }
    if ($RecycleBin) {
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            [void]$notes.Add('Corbeille videe.')
        }
        catch {
            try {
                $shell = New-Object -ComObject Shell.Application
                $shell.NameSpace(0xA).Items() | ForEach-Object { Remove-Item -LiteralPath $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
                [void]$notes.Add('Corbeille videe (COM).')
            }
            catch { [void]$notes.Add('Corbeille: echec.') }
        }
    }
    if ($WuCache) {
        $wu = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
        if (Test-Path -LiteralPath $wu) {
            try {
                Get-ChildItem -LiteralPath $wu -Force -ErrorAction SilentlyContinue |
                    ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { } }
                [void]$notes.Add('Cache Windows Update nettoye.')
            }
            catch { [void]$notes.Add('Cache WU: echec.') }
        }
    }
    if ($Dism) {
        try {
            Start-Process -FilePath 'DISM.exe' -ArgumentList @('/Online', '/Cleanup-Image', '/StartComponentCleanup') -WindowStyle Hidden
            [void]$notes.Add('DISM StartComponentCleanup lance.')
        }
        catch { [void]$notes.Add('DISM: echec.') }
    }
    if ($notes.Count -eq 0) {
        return @{ ok = $false; message = 'Aucun nettoyage selectionne.' }
    }
    return @{ ok = $true; message = ($notes -join ' ') }
}

function Get-FreshAgentStartupAudit {
    $items = [System.Collections.ArrayList]@()
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($rk in $runKeys) {
        if (-not (Test-Path -LiteralPath $rk)) { continue }
        try {
            $props = Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -match '^PS') { continue }
                [void]$items.Add([pscustomobject]@{
                        Source = $rk
                        Name   = $p.Name
                        Command = [string]$p.Value
                        Suggestion = 'Verifier si utile au demarrage.'
                    })
            }
        }
        catch { }
    }
    try {
        Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$items.Add([pscustomobject]@{
                    Source = 'WMI'
                    Name   = $_.Name
                    Command = $_.Command
                    Suggestion = 'Suggestion: desactiver si non essentiel (pas d action auto).'
                })
        }
    }
    catch { }
    return @($items)
}

function Get-FreshAgentServicesAudit {
    param(
        [string]$RepoRef = 'main',
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $suggestions = [System.Collections.ArrayList]@()
    $allow = @()
    if (Get-Command Get-FreshAgentServicesAllowlist -ErrorAction SilentlyContinue) {
        try {
            $cfg = Get-FreshAgentServicesAllowlist -RepoRef $RepoRef -FreshAppData $FreshAppData
            if ($cfg -and $cfg.services) { $allow = @($cfg.services) }
        }
        catch { }
    }
    try {
        Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -eq 'Running' } |
            Select-Object -First 40 |
            ForEach-Object {
                $name = $_.Name
                $hint = if ($allow -contains $name) {
                    'Dans allowlist — OK.'
                }
                else {
                    'Suggestion: verifier utilite (aucune action auto).'
                }
                [void]$suggestions.Add([pscustomobject]@{
                        Name       = $name
                        DisplayName = $_.DisplayName
                        Suggestion = $hint
                    })
            }
    }
    catch { }
    return @($suggestions)
}

function Get-FreshAgentWeeklyHealthReportPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'weekly-health-report.txt'
}

function New-FreshAgentWeeklyHealthReport {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $lines = [System.Collections.ArrayList]@()
    [void]$lines.Add(('Rapport sante Fresh Agent — {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')))
    [void]$lines.Add('')
    if (Get-Command Get-FreshAgentHealthSnapshot -ErrorAction SilentlyContinue) {
        $snap = Get-FreshAgentHealthSnapshot -FreshAppData $FreshAppData
        [void]$lines.Add(('CPU {0}% | RAM {1}% | Disque C: {2} Go libres' -f $snap.cpuPct, $snap.ramUsedPct, $snap.diskFreeGb))
        if ($snap.gpuName) { [void]$lines.Add(('GPU: {0}' -f $snap.gpuName)) }
    }
    $startup = Get-FreshAgentStartupAudit
    [void]$lines.Add('')
    [void]$lines.Add(('Entrees demarrage: {0} (suggestions only)' -f $startup.Count))
    foreach ($s in ($startup | Select-Object -First 8)) {
        [void]$lines.Add(('  - {0}: {1}' -f $s.Name, $s.Suggestion))
    }
    $path = Get-FreshAgentWeeklyHealthReportPath -FreshAppData $FreshAppData
    ($lines -join [Environment]::NewLine) | Set-Content -LiteralPath $path -Encoding UTF8
    return @{ ok = $true; message = "Rapport: $path"; path = $path }
}

function Test-FreshAgentWeeklyReportDue {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [int]$Days = 7
    )
    $marker = Join-Path $FreshAppData 'weekly-health-last.json'
    if (-not (Test-Path -LiteralPath $marker)) { return $true }
    try {
        $raw = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw.at) { return $true }
        return (((Get-Date) - [datetime]$raw.at).TotalDays -ge $Days)
    }
    catch { return $true }
}

function Invoke-FreshAgentWeeklyHealthReportIfDue {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    if (-not (Test-FreshAgentWeeklyReportDue -FreshAppData $FreshAppData)) {
        return $null
    }
    $r = New-FreshAgentWeeklyHealthReport -FreshAppData $FreshAppData
    @{ at = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $FreshAppData 'weekly-health-last.json') -Encoding UTF8
    return $r
}

# --- Skill handlers ---

function Invoke-SkillCleanup {
    param(
        $Temp = $true,
        $RecycleBin = $false,
        $WuCache = $false,
        $Dism = $false,
        $CreateRestorePoint = $true
    )
    # [bool]'false' vaut $true en PowerShell: parser les chaines explicitement.
    $asBool = {
        param($Value, [bool]$Default)
        if (Get-Command ConvertTo-FreshAgentBool -ErrorAction SilentlyContinue) {
            if ($null -eq $Value) { return $Default }
            return (ConvertTo-FreshAgentBool -Value $Value -Default $Default)
        }
        if ($null -eq $Value) { return $Default }
        if ($Value -is [bool]) { return [bool]$Value }
        $s = ([string]$Value).Trim().ToLowerInvariant()
        if ($s -match '^(1|true|yes|oui|on|vrai)$') { return $true }
        if ($s -match '^(0|false|no|non|off|faux)$') { return $false }
        return $Default
    }
    $doTemp = [bool](& $asBool $Temp $true)
    $doRecycle = [bool](& $asBool $RecycleBin $false)
    $doWu = [bool](& $asBool $WuCache $false)
    $doDism = [bool](& $asBool $Dism $false)
    $doRp = [bool](& $asBool $CreateRestorePoint $true)
    return Invoke-FreshAgentCleanup -Temp:$doTemp -RecycleBin:$doRecycle -WuCache:$doWu -Dism:$doDism -CreateRestorePoint:$doRp
}

function Invoke-SkillAuditStartup {
    $items = Get-FreshAgentStartupAudit
    $top = $items | Select-Object -First 12
    $msg = if ($top.Count -eq 0) { 'Aucune entree demarrage detectee.' } else {
        ($top | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Suggestion }) -join ' | '
    }
    return @{ ok = $true; message = $msg; items = $items }
}

function Invoke-SkillAuditServices {
    param(
        [string]$RepoRef = 'main',
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $items = Get-FreshAgentServicesAudit -RepoRef $RepoRef -FreshAppData $FreshAppData
    $top = $items | Select-Object -First 10
    $msg = ($top | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Suggestion }) -join ' | '
    if (-not $msg) { $msg = 'Aucun service auto a auditer.' }
    return @{ ok = $true; message = $msg; items = $items }
}

function Invoke-SkillWeeklyHealthReport {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return New-FreshAgentWeeklyHealthReport -FreshAppData $FreshAppData
}

function Invoke-SkillCreateRestorePoint {
    param([string]$Description = 'Fresh Agent')
    return New-FreshAgentRestorePoint -Description $Description
}
