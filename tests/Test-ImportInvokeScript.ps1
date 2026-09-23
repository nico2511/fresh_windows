#Requires -Version 5.1
$FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
. (Join-Path $FreshAppData 'lib\FreshAgent-Config.ps1')
$path = Join-Path $FreshAppData 'lib\FreshAgent-Dashboard.ps1'
$escaped = $path.Replace("'", "''")
$dot = [scriptblock]::Create(". '$escaped'")
$null = $ExecutionContext.InvokeCommand.InvokeScript($false, $dot, $null, @())
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    Write-Error 'InvokeScript false: Show absent at script scope'
}
Write-Host 'OK InvokeScript parent scope dot-source'
