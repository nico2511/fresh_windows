$files = @(
    'launcher.ps1',
    'scripts\GameMode-Common.ps1',
    'scripts\Invoke-GameModeKill.ps1',
    'scripts\GameMode-WatchAgent.ps1',
    'scripts\lib\Launcher-WinUtil.ps1',
    'scripts\lib\Launcher-GpuMenus.ps1',
    'scripts\lib\Launcher-Tasks.ps1',
    'scripts\lib\Launcher-Core.ps1'
)
$bad = 0
foreach ($f in $files) {
    $errs = $null
    $path = Join-Path $PSScriptRoot $f
    if (-not (Test-Path $path)) { $path = Join-Path (Get-Location) $f }
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        Write-Host "FAIL $f"
        $errs | ForEach-Object { Write-Host $_.Message }
        $bad++
    }
    else {
        Write-Host "OK $f"
    }
}
exit $bad
