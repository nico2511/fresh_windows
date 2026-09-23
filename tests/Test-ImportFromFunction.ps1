#Requires -Version 5.1
function BadImport {
    param([string]$Path)
    $escaped = $Path.Replace("'", "''")
    $null = $ExecutionContext.InvokeCommand.InvokeScript($false, [scriptblock]::Create(". '$escaped'"), $null, @())
}
$p = Join-Path $env:LOCALAPPDATA 'FreshWindows\lib\FreshAgent-Dashboard.ps1'
BadImport $p
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    Write-Error 'Show absent after BadImport'
}
Write-Host 'OK BadImport'
