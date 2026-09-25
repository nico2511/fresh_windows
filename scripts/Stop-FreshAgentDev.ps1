#Requires -Version 5.1
<#
.SYNOPSIS
  Stoppe l'agent FreshWindows-Dev (profil isole).
#>
param(
    [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows-Dev')
)

$ErrorActionPreference = 'Continue'
$stop = Join-Path $FreshAppData 'Stop-FreshWatchAgent.ps1'
if (Test-Path -LiteralPath $stop) {
    & $stop -FreshAppData $FreshAppData
}
else {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match [regex]::Escape($FreshAppData) -and $_.CommandLine -match 'GameMode-WatchAgent' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
Write-Host "Stop Dev demande: $FreshAppData"
