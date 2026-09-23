#Requires -Version 5.1
<#
  Panneau Fresh Agent (clic gauche systray) — toggles et actions sans menu imbrique.
#>

function New-FreshAgentDashboardTabPage {
    param(
        [string]$Title,
        [System.Windows.Forms.TabControl]$TabControl
    )
    $page = New-Object System.Windows.Forms.TabPage
    $page.Text = $Title
    $page.Padding = New-Object System.Windows.Forms.Padding(10)
    $TabControl.TabPages.Add($page) | Out-Null
    return $page
}

function Add-FreshAgentDashboardButton {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 220,
        [int]$H = 32,
        [scriptblock]$OnClick
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.Add_Click($OnClick)
    $Parent.Controls.Add($btn) | Out-Null
    return $btn
}

function Add-FreshAgentDashboardCheck {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [scriptblock]$OnChanged
    )
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $Text
    $cb.AutoSize = $true
    $cb.Location = New-Object System.Drawing.Point($X, $Y)
    $cb.Add_CheckedChanged($OnChanged)
    $Parent.Controls.Add($cb) | Out-Null
    return $cb
}

function Update-FreshAgentDashboardUi {
    param(
        [hashtable]$Ui,
        [hashtable]$State
    )
    if (-not $Ui -or -not $State) { return }
    $Ui._suppress = $true
    try {
        if ($Ui.ChkAuto) { $Ui.ChkAuto.Checked = [bool]$State.AutoSuggestKill }
        if ($Ui.ChkMon) { $Ui.ChkMon.Checked = [bool]$State.MonitorEnabled }
        if ($Ui.ChkAi) { $Ui.ChkAi.Checked = [bool]$State.AiEnabled }
        if ($Ui.ChkRag) { $Ui.ChkRag.Checked = [bool]$State.RagEnabled }
        if ($Ui.LblOllama) {
            $Ui.LblOllama.Text = if ($State.OllamaOk) { 'Ollama : actif' } else { 'Ollama : arrete / injoignable' }
        }
        if ($Ui.LblStt -and $State.SttMessage) {
            $Ui.LblStt.Text = [string]$State.SttMessage
        }
        if ($Ui.LblStatus -and $State.TraySummary) {
            $Ui.LblStatus.Text = [string]$State.TraySummary
        }
        if ($Ui.ChkAi) { $Ui.ChkAi.Enabled = [bool]$State.FreshAgentReady }
        if ($Ui.ChkRag) { $Ui.ChkRag.Enabled = [bool]$State.FreshAgentReady }
        if ($Ui.BtnListen) { $Ui.BtnListen.Enabled = [bool]$State.ListenEnabled }
    }
    finally {
        $Ui._suppress = $false
    }
}

function Invoke-FreshAgentDashboardGetStateSafe {
    param($GetState)
    $sb = $null
    if ($GetState -is [scriptblock]) { $sb = $GetState }
    elseif ($GetState -is [System.Management.Automation.CommandInfo]) { $sb = $GetState.ScriptBlock }
    if (-not $sb) { return @{} }
    try { return & $sb }
    catch { return @{} }
}

function Invoke-FreshAgentDashboardActionSafe {
    param(
        $Action,
        [object[]]$ActionArgs
    )
    $sb = $null
    if ($Action -is [scriptblock]) { $sb = $Action }
    elseif ($Action -is [System.Management.Automation.CommandInfo]) { $sb = $Action.ScriptBlock }
    if (-not $sb) { return }
    try {
        if ($ActionArgs -and $ActionArgs.Count -gt 0) { & $sb @ActionArgs }
        else { & $sb }
    }
    catch { }
}

function Show-FreshAgentDashboard {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Actions,
        [Parameter(Mandatory)]
        [scriptblock]$GetState,
        [string]$Title = 'Fresh Agent'
    )
    if (-not ($GetState -is [scriptblock])) {
        throw 'GetState doit etre un ScriptBlock'
    }

    if ($script:FreshAgentDashboardForm -and -not $script:FreshAgentDashboardForm.IsDisposed) {
        Update-FreshAgentDashboardUi -Ui $script:FreshAgentDashboardUi -State (Invoke-FreshAgentDashboardGetStateSafe -GetState $GetState)
        $script:FreshAgentDashboardForm.Show()
        $script:FreshAgentDashboardForm.BringToFront()
        $script:FreshAgentDashboardForm.Activate()
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(520, 420)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.AutoSize = $false
    $lblStatus.Location = New-Object System.Drawing.Point(12, 8)
    $lblStatus.Size = New-Object System.Drawing.Size(496, 36)
    $lblStatus.Text = 'Fresh Agent'
    $form.Controls.Add($lblStatus) | Out-Null

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(12, 48)
    $tabs.Size = New-Object System.Drawing.Size(496, 320)
    $form.Controls.Add($tabs) | Out-Null

    $ui = @{
        LblStatus = $lblStatus
        _suppress = $false
    }

    # --- Jeu ---
    $tabGame = New-FreshAgentDashboardTabPage -Title 'Jeu' -TabControl $tabs
    $script:FreshAgentDashboardActions = $Actions

    $ui.ChkAuto = Add-FreshAgentDashboardCheck -Parent $tabGame -Text 'Detection auto (suggestions kill)' -X 8 -Y 12 -OnChanged {
        if ($script:FreshAgentDashboardUi._suppress) { return }
        $a = $script:FreshAgentDashboardActions
        if ($a.ToggleAutoSuggest) { Invoke-FreshAgentDashboardActionSafe -Action $a.ToggleAutoSuggest -ActionArgs @($script:FreshAgentDashboardUi.ChkAuto.Checked) }
    }
    $ui.ChkMon = Add-FreshAgentDashboardCheck -Parent $tabGame -Text 'Surveillance CPU / alertes' -X 8 -Y 40 -OnChanged {
        if ($script:FreshAgentDashboardUi._suppress) { return }
        $a = $script:FreshAgentDashboardActions
        if ($a.ToggleMonitor) { Invoke-FreshAgentDashboardActionSafe -Action $a.ToggleMonitor -ActionArgs @($script:FreshAgentDashboardUi.ChkMon.Checked) }
    }
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Mode jeu (liste + launchers)' -X 8 -Y 80 -W 240 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.GameModeKill) { Invoke-FreshAgentDashboardActionSafe -Action $a.GameModeKill }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Fermer launchers inactifs' -X 8 -Y 118 -W 240 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.IdleLaunchers) { Invoke-FreshAgentDashboardActionSafe -Action $a.IdleLaunchers }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Tuer suggestions en attente' -X 8 -Y 156 -W 240 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.PendingKill) { Invoke-FreshAgentDashboardActionSafe -Action $a.PendingKill }
    } | Out-Null

    # --- Skills & profils ---
    $tabSkills = New-FreshAgentDashboardTabPage -Title 'Skills' -TabControl $tabs
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Jeu' -X 8 -Y 12 -W 150 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.ProfileGame) { Invoke-FreshAgentDashboardActionSafe -Action $a.ProfileGame }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Travail' -X 168 -Y 12 -W 150 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.ProfileWork) { Invoke-FreshAgentDashboardActionSafe -Action $a.ProfileWork }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Clean' -X 328 -Y 12 -W 150 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.ProfileClean) { Invoke-FreshAgentDashboardActionSafe -Action $a.ProfileClean }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Etat systeme' -X 8 -Y 56 -W 220 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.SkillHealth) { Invoke-FreshAgentDashboardActionSafe -Action $a.SkillHealth }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Session jeu (DND)' -X 8 -Y 94 -W 220 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.SkillGameSession) { Invoke-FreshAgentDashboardActionSafe -Action $a.SkillGameSession }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Fin session jeu' -X 8 -Y 132 -W 220 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.SkillEndGame) { Invoke-FreshAgentDashboardActionSafe -Action $a.SkillEndGame }
    } | Out-Null

    # --- IA ---
    $tabAi = New-FreshAgentDashboardTabPage -Title 'IA' -TabControl $tabs
    $ui.ChkAi = Add-FreshAgentDashboardCheck -Parent $tabAi -Text 'Intelligence artificielle (Ollama)' -X 8 -Y 12 -OnChanged {
        if ($script:FreshAgentDashboardUi._suppress) { return }
        $a = $script:FreshAgentDashboardActions
        if ($a.SetAiEnabled) { Invoke-FreshAgentDashboardActionSafe -Action $a.SetAiEnabled -ActionArgs @($script:FreshAgentDashboardUi.ChkAi.Checked) }
    }
    $ui.ChkRag = Add-FreshAgentDashboardCheck -Parent $tabAi -Text 'RAG guides Fresh Windows' -X 8 -Y 40 -OnChanged {
        if ($script:FreshAgentDashboardUi._suppress) { return }
        $a = $script:FreshAgentDashboardActions
        if ($a.SetRagEnabled) { Invoke-FreshAgentDashboardActionSafe -Action $a.SetRagEnabled -ActionArgs @($script:FreshAgentDashboardUi.ChkRag.Checked) }
    }
    $ui.LblOllama = New-Object System.Windows.Forms.Label
    $ui.LblOllama.AutoSize = $true
    $ui.LblOllama.Location = New-Object System.Drawing.Point(8, 72)
    $ui.LblOllama.Text = 'Ollama : ?'
    $tabAi.Controls.Add($ui.LblOllama) | Out-Null
    $ui.LblStt = New-Object System.Windows.Forms.Label
    $ui.LblStt.AutoSize = $true
    $ui.LblStt.Location = New-Object System.Drawing.Point(8, 92)
    $ui.LblStt.Text = 'STT : ?'
    $tabAi.Controls.Add($ui.LblStt) | Out-Null

    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Demarrer Ollama' -X 8 -Y 120 -W 160 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.StartOllama) { Invoke-FreshAgentDashboardActionSafe -Action $a.StartOllama }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Telecharger modele' -X 176 -Y 120 -W 160 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.EnsureModel) { Invoke-FreshAgentDashboardActionSafe -Action $a.EnsureModel }
    } | Out-Null
    $ui.BtnListen = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Ecouter (STT)' -X 8 -Y 158 -W 160 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.VoiceListen) { Invoke-FreshAgentDashboardActionSafe -Action $a.VoiceListen }
    }
    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Cycle TTS' -X 176 -Y 158 -W 160 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.TtsCycle) { Invoke-FreshAgentDashboardActionSafe -Action $a.TtsCycle }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Tester IA (prompt)' -X 8 -Y 196 -W 160 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.AiTest) { Invoke-FreshAgentDashboardActionSafe -Action $a.AiTest }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Historique IA' -X 176 -Y 196 -W 160 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.AiHistory) { Invoke-FreshAgentDashboardActionSafe -Action $a.AiHistory }
    } | Out-Null

    # --- Fresh Windows ---
    $tabFw = New-FreshAgentDashboardTabPage -Title 'Fresh Windows' -TabControl $tabs
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Menu interactif (admin)' -X 8 -Y 12 -W 240 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.FwMenu) { Invoke-FreshAgentDashboardActionSafe -Action $a.FwMenu }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Maintenance WinUtil' -X 8 -Y 50 -W 240 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.FwMaintenance) { Invoke-FreshAgentDashboardActionSafe -Action $a.FwMaintenance }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Mode jeu (launcher admin)' -X 8 -Y 88 -W 240 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.FwGameMode) { Invoke-FreshAgentDashboardActionSafe -Action $a.FwGameMode }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Mettre a jour scripts locaux' -X 8 -Y 126 -W 240 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.SyncScripts) { Invoke-FreshAgentDashboardActionSafe -Action $a.SyncScripts }
    } | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'PowerShell (sans admin)' -X 8 -Y 164 -W 240 -OnClick {
        $a = $script:FreshAgentDashboardActions
        if ($a.OpenPowerShell) { Invoke-FreshAgentDashboardActionSafe -Action $a.OpenPowerShell }
    } | Out-Null

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Fermer'
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnClose.Location = New-Object System.Drawing.Point(332, 378)
    $btnClose.Size = New-Object System.Drawing.Size(84, 28)
    $form.Controls.Add($btnClose) | Out-Null
    $form.CancelButton = $btnClose

    $btnQuit = New-Object System.Windows.Forms.Button
    $btnQuit.Text = 'Quitter agent'
    $btnQuit.Location = New-Object System.Drawing.Point(424, 378)
    $btnQuit.Size = New-Object System.Drawing.Size(84, 28)
    $btnQuit.Add_Click({
            $a = $script:FreshAgentDashboardActions
        if ($a.QuitAgent) { Invoke-FreshAgentDashboardActionSafe -Action $a.QuitAgent }
        })
    $form.Controls.Add($btnQuit) | Out-Null

    $refreshTimer = New-Object System.Windows.Forms.Timer
    $refreshTimer.Interval = 4000
    $refreshTimer.Add_Tick({
            if ($form.IsDisposed) { return }
            try {
                if (-not $script:FreshAgentDashboardGetState) { return }
                Update-FreshAgentDashboardUi -Ui $script:FreshAgentDashboardUi -State (Invoke-FreshAgentDashboardGetStateSafe -GetState $script:FreshAgentDashboardGetState)
            }
            catch { }
        })
    $refreshTimer.Start()
    $form.Add_FormClosed({
            $refreshTimer.Stop()
            $refreshTimer.Dispose()
        })

    $script:FreshAgentDashboardForm = $form
    $script:FreshAgentDashboardUi = $ui
    $script:FreshAgentDashboardGetState = if ($GetState -is [scriptblock]) {
        $GetState
    }
    else {
        (Get-Command Get-FreshAgentDashboardState -CommandType Function -ErrorAction Stop).ScriptBlock
    }

    Update-FreshAgentDashboardUi -Ui $ui -State (Invoke-FreshAgentDashboardGetStateSafe -GetState $GetState)
    [void]$form.Show($script:HiddenForm)
}

function Update-FreshAgentDashboardIfOpen {
    if (-not $script:FreshAgentDashboardForm -or $script:FreshAgentDashboardForm.IsDisposed) { return }
    if (-not $script:FreshAgentDashboardGetState) { return }
    Update-FreshAgentDashboardUi -Ui $script:FreshAgentDashboardUi -State (Invoke-FreshAgentDashboardGetStateSafe -GetState $script:FreshAgentDashboardGetState)
}
