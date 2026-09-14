#Requires -Version 5.1
<#
  Lance Validate-Configs + Pester (si module disponible).
  Exit 0 = OK, 1 = echec.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSCommandPath -Parent
$failed = 0

Write-Host "=== Validate-Configs ===" -ForegroundColor Cyan
& (Join-Path $root 'Validate-Configs.ps1')
if ($LASTEXITCODE -ne 0) { $failed++ }

if (Get-Module -ListAvailable -Name Pester) {
    Write-Host "`n=== Pester Launcher-Core ===" -ForegroundColor Cyan
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = Join-Path $root 'Launcher-Core.Tests.ps1'
    $pesterConfig.Output.Verbosity = 'Detailed'
    $result = Invoke-Pester -Configuration $pesterConfig
    if ($result.FailedCount -gt 0) { $failed++ }
}
else {
    Write-Host "`nPester non installé - tests Launcher-Core ignorés (winget install Pester.Pester)." -ForegroundColor DarkYellow
}

if ($failed -gt 0) {
    Write-Host "`n$failed suite(s) en échec." -ForegroundColor Red
    exit 1
}
Write-Host "`nTous les tests OK." -ForegroundColor Green
exit 0
