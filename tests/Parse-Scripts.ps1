$files = @(
    'launcher.ps1',
    'scripts\GameMode-Common.ps1',
    'scripts\Invoke-GameModeKill.ps1',
    'scripts\Sync-FreshWindowsAgent.ps1',
    'scripts\lib\Launcher-WinUtil.ps1',
    'scripts\lib\Launcher-GpuMenus.ps1',
    'scripts\lib\Launcher-Tasks.ps1',
    'scripts\lib\Launcher-Core.ps1',
    'scripts\lib\FreshWindows-AppxBloatware.ps1',
    'scripts\lib\FreshWindows-BackgroundAudit.ps1',
    'scripts\Invoke-FreshWindowsBackgroundAudit.ps1',
    'scripts\Uninstall-FreshWindows.ps1',
    'scripts\lib\FreshWindows-Uninstall.ps1'
)
function Test-FreshPs1Utf8Bom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$RelativePath = ''
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $nonAscii = $false
    foreach ($b in $bytes) {
        if ($b -gt 127) { $nonAscii = $true; break }
    }
    # launcher.ps1 : pas de BOM (irm | iex) ; contenu ASCII pour PS 5.1 en local.
    if ($RelativePath -eq 'launcher.ps1') {
        if ($hasBom) { return $false }
        return $true
    }
    # Windows PowerShell 5.1 lit un .ps1 sans BOM dans la page ANSI, pas en UTF-8.
    if ($nonAscii -and -not $hasBom) { return $false }
    return $true
}

$bad = 0
$repoRoot = Split-Path $PSScriptRoot -Parent
Write-Host "=== UTF-8 BOM (PS 5.1) ==="
Get-ChildItem -LiteralPath $repoRoot -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    ForEach-Object {
        $rel = $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
        if (Test-FreshPs1Utf8Bom -Path $_.FullName -RelativePath $rel) {
            Write-Host "OK BOM $rel"
        }
        else {
            if ($rel -eq 'launcher.ps1') {
                Write-Host "FAIL BOM $rel (UTF-8 BOM interdit sur launcher.ps1)"
            }
            else {
                Write-Host "FAIL BOM $rel (non-ASCII sans UTF-8 BOM)"
            }
            $bad++
        }
    }

Write-Host ""
Write-Host "=== Parser PS (AST) ==="
foreach ($rel in $files) {
    $path = Join-Path $repoRoot $rel
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "FAIL missing $rel"
        $bad++
        continue
    }
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Write-Host "FAIL parse $rel"
        $errors | ForEach-Object { Write-Host "  $($_.Message)" }
        $bad++
    }
    else {
        Write-Host "OK parse $rel"
    }
}

if ($bad -gt 0) { exit 1 }
Write-Host "Parse-Scripts OK." -ForegroundColor Green
exit 0
