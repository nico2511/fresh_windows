#Requires -Version 5.1
<#
.SYNOPSIS
  Audit arriere-plan Fresh Windows (lecture seule par defaut).
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-FreshWindowsBackgroundAudit.ps1
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-FreshWindowsBackgroundAudit.ps1 -Apply -TargetIds scheduled-task-watch-agent,prefs-monitor-off
#>
param(
    [switch]$Apply,
    [switch]$Restore,
    [string[]]$TargetIds = @(),
    [switch]$NoConfirm,
    [string]$FreshAppData = '',
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'

function Resolve-FreshWindowsBackgroundAuditLib {
    param([string]$FreshAppData)
    $candidates = @()
    if ($PSScriptRoot) {
        $candidates += (Join-Path $PSScriptRoot 'lib\FreshWindows-BackgroundAudit.ps1')
        $parent = Split-Path $PSScriptRoot -Parent
        if ($parent) {
            $candidates += (Join-Path $parent 'scripts\lib\FreshWindows-BackgroundAudit.ps1')
        }
    }
    if ($FreshAppData) {
        $candidates += (Join-Path $FreshAppData 'lib\FreshWindows-BackgroundAudit.ps1')
    }
    else {
        $candidates += (Join-Path $env:LOCALAPPDATA 'FreshWindows\lib\FreshWindows-BackgroundAudit.ps1')
    }
    foreach ($p in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    throw 'FreshWindows-BackgroundAudit.ps1 introuvable. Sync scripts locaux (menu Fresh Windows).'
}

if ([string]::IsNullOrWhiteSpace($FreshAppData)) {
    $FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
}

$lib = Resolve-FreshWindowsBackgroundAuditLib -FreshAppData $FreshAppData
. $lib

$splat = @{
    FreshAppData = $FreshAppData
}
if ($Apply) { $splat.Apply = $true }
if ($Restore) { $splat.Restore = $true }
if ($TargetIds -and $TargetIds.Count -gt 0) { $splat.TargetIds = $TargetIds }
if ($NoConfirm) { $splat.NoConfirm = $true }
if ($ReportPath) { $splat.ReportPath = $ReportPath }

$result = Invoke-FreshWindowsBackgroundAudit @splat
if ($result -and $result.ok -eq $false -and $result.mode -eq 'apply-cancelled') {
    exit 2
}
if ($result -and $result.ok -eq $false) {
    exit 1
}
exit 0
