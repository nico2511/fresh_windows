#Requires -Version 5.1
# Valide le dot-source dashboard dans un runspace STA (meme pattern que l agent).
$ErrorActionPreference = 'Stop'
$path = Join-Path $env:LOCALAPPDATA 'FreshWindows\lib\FreshAgent-Dashboard.ps1'
if (-not (Test-Path -LiteralPath $path)) {
    Write-Error "Dashboard absent: $path"
}
$rs = [runspacefactory]::CreateRunspace()
$rs.ThreadOptions = 'ReuseThread'
$rs.ApartmentState = [Threading.ApartmentState]::STA
$rs.Open()
try {
    $null = $rs.SessionStateProxy.InvokeCommand.InvokeScript('Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction SilentlyContinue')
    $escaped = $path.Replace("'", "''")
    $null = $rs.SessionStateProxy.InvokeCommand.InvokeScript(". '$escaped'")
    $hasInRs = [bool]($rs.SessionStateProxy.InvokeCommand.InvokeScript('Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue'))
    if (-not $hasInRs) {
        Write-Error 'Show-FreshAgentDashboard absent dans le runspace apres dot-source'
    }
}
finally {
    $rs.Close()
}

$script:WatchAgentSessionState = $ExecutionContext.SessionState
$dot = [scriptblock]::Create(". '$($path.Replace("'", "''"))'")
$null = $script:WatchAgentSessionState.InvokeCommand.InvokeScript($false, $dot, $null, @())
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    Write-Error 'Show-FreshAgentDashboard absent apres InvokeScript($false) dans la session script'
}
Write-Host 'OK runspace + InvokeScript dashboard import'
