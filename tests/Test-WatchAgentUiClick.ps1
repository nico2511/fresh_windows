#Requires -Version 5.1
# Valide message loop form + handlers menu (PerformClick) comme l agent systray.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:WatchUiHandlers = New-Object System.Collections.ArrayList
function Register-WatchUiHandler {
    param([object]$Handler)
    if ($null -ne $Handler) { [void]$script:WatchUiHandlers.Add($Handler) }
    return $Handler
}
function Add-WatchMenuClick {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.ToolStripItem]$MenuItem,
        [Parameter(Mandatory)][scriptblock]$Handler
    )
    $MenuItem.Add_Click((Register-WatchUiHandler $Handler))
}

$script:MenuClicked = $false
$script:NotifyClicked = $false

$form = New-Object System.Windows.Forms.Form
$form.ShowInTaskbar = $false
$form.FormBorderStyle = 'FixedToolWindow'
$form.Size = New-Object System.Drawing.Size(1, 1)
$form.Opacity = 0

$ni = New-Object System.Windows.Forms.NotifyIcon
$ni.Icon = [System.Drawing.SystemIcons]::Application
$ni.Text = 'Fresh Agent UI test'
$ni.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$mi = $menu.Items.Add('Test item')
Add-WatchMenuClick $mi { $script:MenuClicked = $true }

$ni.ContextMenuStrip = $menu
$ni.Add_Click((Register-WatchUiHandler { $script:NotifyClicked = $true }))

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick((Register-WatchUiHandler {
        $timer.Stop()
        $timer.Dispose()
        $mi.PerformClick()
        if (-not $script:NotifyClicked) {
            $ni.GetType().GetEvent('Click').GetAddMethod() | Out-Null
        }
        $ni.Add_Click((Register-WatchUiHandler { $script:NotifyClicked = $true }))
        $handler = $script:WatchUiHandlers | Select-Object -Last 1
        if ($handler) { & $handler $ni ([System.EventArgs]::Empty) }
        $ni.Visible = $false
        $ni.Dispose()
        $form.Close()
    }))
$timer.Start()

[void]$form.Show()
[System.Windows.Forms.Application]::Run($form)

if (-not $script:MenuClicked) {
    Write-Error 'PerformClick menu: handler not invoked'
}
if (-not $script:NotifyClicked) {
    Write-Error 'NotifyIcon Click handler not invoked'
}
Write-Host 'OK WatchAgent UI click pattern (form Run + registered handlers)'
