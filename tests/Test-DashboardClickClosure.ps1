#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:WatchAgentSessionState = $ExecutionContext.SessionState
$script:Clicked = $false
$script:Toggled = $null

function Invoke-GameModeKillNow { $script:Clicked = $true }
function Set-Toggle([bool]$On) { $script:Toggled = $On }

. (Join-Path $PSScriptRoot '..\scripts\lib\FreshAgent-Dashboard.ps1')

$script:FreshAgentDashboardActions = @{
    GameModeKill      = { Invoke-GameModeKillNow }
    ToggleAutoSuggest = { param([bool]$On) Set-Toggle -On $On }
}
$script:FreshAgentDashboardUi = @{ _suppress = $false }

$form = New-Object System.Windows.Forms.Form
$form.Opacity = 0
$form.ShowInTaskbar = $false
$btn = Add-FreshAgentDashboardButton -Parent $form -Text 'X' -X 0 -Y 0 -ActionKey 'GameModeKill'
$chk = Add-FreshAgentDashboardCheck -Parent $form -Text 'Y' -X 0 -Y 40 -ActionKey 'ToggleAutoSuggest'

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
        $timer.Stop()
        $btn.PerformClick()
        $chk.Checked = $true
        $form.Close()
    })
$timer.Start()
[void]$form.Show()
[System.Windows.Forms.Application]::Run($form)

if (-not $script:Clicked) { Write-Error 'Button SessionState dispatch failed' }
if ($script:Toggled -ne $true) { Write-Error 'Checkbox SessionState dispatch failed' }
Write-Host 'OK dashboard SessionState action dispatch'
