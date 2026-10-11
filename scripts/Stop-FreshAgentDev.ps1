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
    $repoStop = Join-Path $PSScriptRoot 'Stop-FreshWatchAgent.ps1'
    if (Test-Path -LiteralPath $repoStop) {
        & $repoStop -FreshAppData $FreshAppData
    }
}
Write-Host "Stop Dev demande: $FreshAppData"
