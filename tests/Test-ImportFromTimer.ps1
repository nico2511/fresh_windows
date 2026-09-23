#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
$script:WatchAgentSessionState = $ExecutionContext.SessionState
. (Join-Path $FreshAppData 'lib\FreshAgent-Config.ps1')

function Simulate-TimerImport {
    $ok = Import-FreshAgentModule -RelativePath 'lib/FreshAgent-Dashboard.ps1' -FreshAppData $FreshAppData
    Write-Host "Import-FreshAgentModule ok=$ok show=$( [bool](Get-Command Show-FreshAgentDashboard -EA SilentlyContinue) )"
}

$form = New-Object Windows.Forms.Form
$form.Add_Load({ Simulate-TimerImport })
[void]$form.ShowDialog()

if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    Write-Error 'Show missing after timer-simulated import'
}
Write-Host 'OK timer import'
