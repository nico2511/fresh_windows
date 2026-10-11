#Requires -Version 5.1
<#
.SYNOPSIS
  Lance Fresh Agent sur le profil AppData isole FreshWindows-Dev.
#>
param(
    [string]$RepoRoot = '',
    [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows-Dev')
)

$ErrorActionPreference = 'Stop'

function Test-FreshAgentRepoRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'scripts\GameMode-WatchAgent.ps1'))
}

function Resolve-FreshAgentDevRepoRoot {
    param([string]$Hint = '', [string]$FreshAppData)
    if (Test-FreshAgentRepoRoot -Path $Hint) { return (Resolve-Path -LiteralPath $Hint).Path }
    if (Test-FreshAgentRepoRoot -Path $env:FRESH_WIN_REPO) {
        return (Resolve-Path -LiteralPath $env:FRESH_WIN_REPO).Path
    }
    $marker = Join-Path $FreshAppData 'repo.root'
    if (Test-Path -LiteralPath $marker) {
        $fromMarker = (Get-Content -LiteralPath $marker -Raw -ErrorAction SilentlyContinue).Trim()
        if (Test-FreshAgentRepoRoot -Path $fromMarker) {
            return (Resolve-Path -LiteralPath $fromMarker).Path
        }
    }
    $fromScript = Split-Path $PSScriptRoot -Parent
    if (Test-FreshAgentRepoRoot -Path $fromScript) {
        return (Resolve-Path -LiteralPath $fromScript).Path
    }
    foreach ($c in @(
            'D:\Git\FreshWindows',
            (Join-Path $env:USERPROFILE 'Git\FreshWindows'),
            (Join-Path $env:USERPROFILE 'source\repos\FreshWindows')
        )) {
        if (Test-FreshAgentRepoRoot -Path $c) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return $null
}

$RepoRoot = Resolve-FreshAgentDevRepoRoot -Hint $RepoRoot -FreshAppData $FreshAppData
if (-not $RepoRoot) {
    throw "Depot FreshWindows introuvable. Passe -RepoRoot ou definis FRESH_WIN_REPO."
}

$sync = Join-Path $RepoRoot 'scripts\Dev-SyncFreshAgentFromRepo.ps1'
& $sync -RepoRoot $RepoRoot -FreshAppData $FreshAppData

$stop = Join-Path $PSScriptRoot 'Stop-FreshAgentDev.ps1'
& $stop -FreshAppData $FreshAppData

$agent = Join-Path $FreshAppData 'GameMode-WatchAgent.ps1'
if (-not (Test-Path -LiteralPath $agent)) {
    throw "GameMode-WatchAgent.ps1 manquant: $agent"
}

$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
Write-Host "Demarrage agent Dev: $FreshAppData" -ForegroundColor Cyan

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $psExe
$psi.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$agent`""
$psi.WorkingDirectory = $FreshAppData
$psi.UseShellExecute = $false
$psi.EnvironmentVariables['FRESH_WIN_APPDATA'] = $FreshAppData
if ($env:FRESH_WIN_REF) {
    $psi.EnvironmentVariables['FRESH_WIN_REF'] = $env:FRESH_WIN_REF
}
$proc = [System.Diagnostics.Process]::Start($psi)
Write-Host ("PID agent: {0}" -f $proc.Id) -ForegroundColor DarkGray
