#Requires -Version 5.1
# Valide dispatch dashboard : Tag ActionKey + $script:FreshAgentDashboardActions
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

. (Join-Path $PSScriptRoot '..\scripts\lib\FreshAgent-Dashboard.ps1')

$script:Clicked = $false
$script:Toggled = $null
$script:FreshAgentDashboardActions = @{
    GameModeKill      = { $script:Clicked = $true }
    ToggleAutoSuggest = { param([bool]$On) $script:Toggled = $On }
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

if (-not $script:Clicked) { Write-Error 'Button ActionKey dispatch failed' }
if ($script:Toggled -ne $true) { Write-Error 'Checkbox ActionKey dispatch failed' }
Write-Host 'OK dashboard Tag ActionKey clicks'
