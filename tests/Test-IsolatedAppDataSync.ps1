#Requires -Version 5.1
<#
  Simule Dev-Sync vers un AppData isole (une seule source: le clone).
  Verifie que GameMode-WatchAgent + Dashboard copie == repo (hash).
#>
param(
    [string]$FreshAppData = '',
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
else {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$ownedTemp = $false
$fresh = $FreshAppData
if ([string]::IsNullOrWhiteSpace($fresh)) {
    $fresh = Join-Path ([IO.Path]::GetTempPath()) ('FreshWindows-IsolatedTest-' + [guid]::NewGuid().ToString('n'))
    $ownedTemp = $true
    New-Item -ItemType Directory -Path $fresh -Force | Out-Null
    $syncScript = Join-Path $RepoRoot 'scripts\Dev-SyncFreshAgentFromRepo.ps1'
    & $syncScript -RepoRoot $RepoRoot -FreshAppData $fresh
}

try {

    $pairs = @(
        @('scripts\GameMode-WatchAgent.ps1', 'GameMode-WatchAgent.ps1'),
        @('scripts\lib\FreshAgent-Dashboard.ps1', 'lib\FreshAgent-Dashboard.ps1'),
        @('scripts\Stop-FreshWatchAgent.ps1', 'Stop-FreshWatchAgent.ps1')
    )
    foreach ($pair in $pairs) {
        $src = Join-Path $repoRoot ($pair[0] -replace '\\', [IO.Path]::DirectorySeparatorChar)
        $dst = Join-Path $fresh ($pair[1] -replace '\\', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $src)) { throw "Repo manquant: $src" }
        if (-not (Test-Path -LiteralPath $dst)) { throw "Copie manquante: $dst" }
        function Get-FreshScriptTextNoBom {
            param([string]$Path)
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                return $utf8NoBom.GetString($bytes, 3, $bytes.Length - 3)
            }
            return $utf8NoBom.GetString($bytes)
        }
        $t1 = Get-FreshScriptTextNoBom -Path $src
        $t2 = Get-FreshScriptTextNoBom -Path $dst
        if ($t1 -ne $t2) {
            throw ("Contenu different apres sync (sans BOM): {0}" -f $pair[1])
        }
    }

    $ref = (Get-Content -LiteralPath (Join-Path $fresh 'scripts.ref') -Raw).Trim()
    if ($ref -ne 'local-dev') { throw "scripts.ref attendu local-dev, got: $ref" }

    Write-Host "OK isolated AppData sync ($fresh)" -ForegroundColor Green
    Write-Host $fresh
}
finally {
    if ($ownedTemp -and (Test-Path -LiteralPath $fresh)) {
        Remove-Item -LiteralPath $fresh -Recurse -Force -ErrorAction SilentlyContinue
    }
}
