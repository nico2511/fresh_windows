#Requires -Version 5.1
<#
  Overlay discret Fresh Agent (remplace les ballons invasifs pour voix / skills / IA).
#>

function Show-FreshAgentOverlay {
    param(
        [string]$Title = 'Fresh Agent',
        [string]$Text = '',
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info',
        [int]$FadeMs = 4000
    )
    if (-not ('System.Windows.Forms.Form' -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    }

    $msg = if ([string]::IsNullOrWhiteSpace($Text)) { $Title } else { ($Title + ' - ' + $Text) }
    if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 117) + '...' }

    if ($script:FreshAgentOverlayForm -and -not $script:FreshAgentOverlayForm.IsDisposed) {
        try {
            if ($script:FreshAgentOverlayLabel -and -not $script:FreshAgentOverlayLabel.IsDisposed) {
                $script:FreshAgentOverlayLabel.Text = $msg
            }
            $script:FreshAgentOverlayForm.Show()
            $script:FreshAgentOverlayForm.BringToFront()
            if ($script:FreshAgentOverlayTimer) {
                $script:FreshAgentOverlayTimer.Stop()
                $script:FreshAgentOverlayTimer.Interval = [Math]::Max(1500, $FadeMs)
                $script:FreshAgentOverlayTimer.Start()
            }
            return
        }
        catch { }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.StartPosition = 'Manual'
    $form.Size = New-Object System.Drawing.Size(320, 56)
    $form.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 40)
    $form.Opacity = 0.92

    $accent = switch ($Level) {
        'Warning' { [System.Drawing.Color]::FromArgb(220, 160, 60) }
        'Error' { [System.Drawing.Color]::FromArgb(200, 80, 80) }
        default { [System.Drawing.Color]::FromArgb(70, 140, 220) }
    }
    $bar = New-Object System.Windows.Forms.Panel
    $bar.BackColor = $accent
    $bar.Location = New-Object System.Drawing.Point(0, 0)
    $bar.Size = New-Object System.Drawing.Size(4, 56)
    $form.Controls.Add($bar) | Out-Null

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(235, 238, 245)
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $lbl.Location = New-Object System.Drawing.Point(14, 10)
    $lbl.Size = New-Object System.Drawing.Size(290, 36)
    $lbl.Text = $msg
    $form.Controls.Add($lbl) | Out-Null

    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Location = New-Object System.Drawing.Point(($wa.Right - $form.Width - 18), ($wa.Bottom - $form.Height - 18))

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [Math]::Max(1500, $FadeMs)
    $timer.Add_Tick({
            try {
                if ($script:FreshAgentOverlayForm -and -not $script:FreshAgentOverlayForm.IsDisposed) {
                    $script:FreshAgentOverlayForm.Hide()
                }
            }
            catch { }
            try { $script:FreshAgentOverlayTimer.Stop() } catch { }
        })

    $script:FreshAgentOverlayForm = $form
    $script:FreshAgentOverlayLabel = $lbl
    $script:FreshAgentOverlayTimer = $timer
    [void]$form.Show()
    $timer.Start()
}

function Hide-FreshAgentOverlay {
    try {
        if ($script:FreshAgentOverlayTimer) { $script:FreshAgentOverlayTimer.Stop() }
        if ($script:FreshAgentOverlayForm -and -not $script:FreshAgentOverlayForm.IsDisposed) {
            $script:FreshAgentOverlayForm.Hide()
        }
    }
    catch { }
}
