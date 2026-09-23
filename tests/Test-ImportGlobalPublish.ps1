#Requires -Version 5.1
function Import-TestModule {
    param([string]$Path)
    $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    Get-ChildItem -Path Function: | ForEach-Object { [void]$known.Add($_.Name) }
    . $Path
    Get-ChildItem -Path Function: | Where-Object { -not $known.Contains($_.Name) } | ForEach-Object {
        Set-Item -Path ("global:\function:{0}" -f $_.Name) -Value $_.ScriptBlock -Force
    }
}
$path = Join-Path $env:LOCALAPPDATA 'FreshWindows\lib\FreshAgent-Dashboard.ps1'
Import-TestModule -Path $path
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    Write-Error 'global publish failed'
}
Write-Host 'OK global publish from function import'
