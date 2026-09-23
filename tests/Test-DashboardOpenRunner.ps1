#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$script:WatchAgentSessionState = $ExecutionContext.SessionState
$script:FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
$dashPath = Join-Path $script:FreshAppData 'lib\FreshAgent-Dashboard.ps1'
$escapedDash = $dashPath.Replace("'", "''")
$runner = [scriptblock]::Create(@"
param(`$Act, `$St)
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    . '$escapedDash'
}
if (-not (Get-Command Show-FreshAgentDashboard -ErrorAction SilentlyContinue)) {
    throw 'Show absent'
}
'OK'
"@)
$form = New-Object Windows.Forms.Form
$form.Add_Load({
        $null = $script:WatchAgentSessionState.InvokeCommand.InvokeScript($false, $runner, $null, @($null, $null))
        $form.Close()
    })
[void]$form.ShowDialog()
Write-Host 'OK dashboard runner from UI load'
