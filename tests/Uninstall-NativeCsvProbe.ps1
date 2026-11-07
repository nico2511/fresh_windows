#Requires -Version 5.1
<#
  Sonde frontiere powershell.exe -File : valide -ImmuneProcessIdsCsv sans tuer de processus.
  Usage (Windows, non destructif) :
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Uninstall-NativeCsvProbe.ps1 -ImmuneProcessIdsCsv "123,456"
#>
param(
    [Parameter(Mandatory)][string]$ImmuneProcessIdsCsv,
    [string]$LibPath = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LibPath)) {
    $LibPath = Join-Path (Split-Path $PSCommandPath -Parent) '..\scripts\lib\FreshWindows-Uninstall.ps1'
    $LibPath = [System.IO.Path]::GetFullPath($LibPath)
}
if (-not (Test-Path -LiteralPath $LibPath)) {
    Write-Host "Lib introuvable : $LibPath" -ForegroundColor Red
    exit 2
}

. $LibPath -DryRun -ImmuneProcessIdsCsv $ImmuneProcessIdsCsv
$parts = @($ImmuneProcessIdsCsv.Split(','))
foreach ($part in $parts) {
    $token = ([string]$part).Trim()
    if ($token -notmatch '^\d+$') { continue }
    $id = [int]$token
    if (-not (Test-FreshUninstallProcessImmune -ProcessId $id -CommandLine '')) {
        Write-Host "PID $id non immunitaire" -ForegroundColor Red
        exit 1
    }
}
Write-Host 'NativeCsvProbe OK' -ForegroundColor Green
exit 0
