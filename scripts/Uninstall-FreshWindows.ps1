#Requires -RunAsAdministrator
#Requires -Version 5.1
# Wrapper CLI : logique dans scripts/lib/FreshWindows-Uninstall.ps1
param(
    [switch]$DryRun,
    [switch]$ReinstallAfter,
    [switch]$Confirmed,
    [int[]]$ImmuneProcessIds = @(),
    [string]$OwnedSessionId = '',
    [string]$SandboxLocalAppDataRoot = ''
)

$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib\FreshWindows-Uninstall.ps1'
if (-not (Test-Path -LiteralPath $lib)) {
    Write-Host "Bibliotheque FreshWindows-Uninstall.ps1 introuvable a cote du wrapper." -ForegroundColor Red
    exit 1
}
. $lib @PSBoundParameters
if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = Invoke-FreshWindowsUninstall
    exit $exitCode
}
