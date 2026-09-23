#Requires -Version 5.1
<#
  Panneau Fresh Agent (clic gauche systray) — toggles et actions sans menu imbrique.
  Les handlers WinForms doivent invoquer des ScriptBlock via Tag / $script: (pas de Function: lookup).
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
        [Parameter(Mandatory)][string]$ActionKey
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.Tag = $ActionKey
    $btn.Add_Click({
            param($sender, $e)
            try {
                $key = [string]$sender.Tag
                if ([string]::IsNullOrWhiteSpace($key)) { return }
                $map = $script:FreshAgentDashboardActions
                if (-not $map) { return }
                $sb = $map[$key]
                if ($sb -is [scriptblock]) { & $sb }
            }
            catch { }
        })
    $Parent.Controls.Add($btn) | Out-Null
    return $btn
}

function Add-FreshAgentDashboardCheck {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$X,
        [int]$Y,
        [Parameter(Mandatory)][string]$ActionKey
    )
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $Text
    $cb.AutoSize = $true
    $cb.Location = New-Object System.Drawing.Point($X, $Y)
    $cb.Tag = $ActionKey
    $cb.Add_CheckedChanged({
            param($sender, $e)
            try {
                if ($script:FreshAgentDashboardUi -and $script:FreshAgentDashboardUi._suppress) { return }
                $key = [string]$sender.Tag
                if ([string]::IsNullOrWhiteSpace($key)) { return }
                $map = $script:FreshAgentDashboardActions
                if (-not $map) { return }
                $sb = $map[$key]
                if ($sb -is [scriptblock]) { & $sb ([bool]$sender.Checked) }
            }
            catch { }
        })
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

function Get-FreshAgentDashboardStateSafe {
    param($GetState)
    $sb = $null
    if ($GetState -is [scriptblock]) { $sb = $GetState }
    elseif ($GetState -is [System.Management.Automation.CommandInfo]) { $sb = $GetState.ScriptBlock }
    if (-not $sb) { return @{} }
    try { return & $sb }
    catch { return @{} }
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

    $script:FreshAgentDashboardActions = $Actions
    $script:FreshAgentDashboardGetState = $GetState

    if ($script:FreshAgentDashboardForm -and -not $script:FreshAgentDashboardForm.IsDisposed) {
        Update-FreshAgentDashboardUi -Ui $script:FreshAgentDashboardUi -State (Get-FreshAgentDashboardStateSafe -GetState $GetState)
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
    $ui.ChkAuto = Add-FreshAgentDashboardCheck -Parent $tabGame -Text 'Detection auto (suggestions kill)' -X 8 -Y 12 -ActionKey 'ToggleAutoSuggest'
    $ui.ChkMon = Add-FreshAgentDashboardCheck -Parent $tabGame -Text 'Surveillance CPU / alertes' -X 8 -Y 40 -ActionKey 'ToggleMonitor'
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Mode jeu (liste + launchers)' -X 8 -Y 80 -W 240 -ActionKey 'GameModeKill' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Fermer launchers inactifs' -X 8 -Y 118 -W 240 -ActionKey 'IdleLaunchers' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Tuer suggestions en attente' -X 8 -Y 156 -W 240 -ActionKey 'PendingKill' | Out-Null

    # --- Skills & profils ---
    $tabSkills = New-FreshAgentDashboardTabPage -Title 'Skills' -TabControl $tabs
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Jeu' -X 8 -Y 12 -W 150 -ActionKey 'ProfileGame' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Travail' -X 168 -Y 12 -W 150 -ActionKey 'ProfileWork' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Clean' -X 328 -Y 12 -W 150 -ActionKey 'ProfileClean' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Etat systeme' -X 8 -Y 56 -W 220 -ActionKey 'SkillHealth' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Session jeu (DND)' -X 8 -Y 94 -W 220 -ActionKey 'SkillGameSession' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Fin session jeu' -X 8 -Y 132 -W 220 -ActionKey 'SkillEndGame' | Out-Null

    # --- IA ---
    $tabAi = New-FreshAgentDashboardTabPage -Title 'IA' -TabControl $tabs
    $ui.ChkAi = Add-FreshAgentDashboardCheck -Parent $tabAi -Text 'Intelligence artificielle (Ollama)' -X 8 -Y 12 -ActionKey 'SetAiEnabled'
    $ui.ChkRag = Add-FreshAgentDashboardCheck -Parent $tabAi -Text 'RAG guides Fresh Windows' -X 8 -Y 40 -ActionKey 'SetRagEnabled'
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

    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Demarrer Ollama' -X 8 -Y 120 -W 160 -ActionKey 'StartOllama' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Telecharger modele' -X 176 -Y 120 -W 160 -ActionKey 'EnsureModel' | Out-Null
    $ui.BtnListen = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Ecouter (STT)' -X 8 -Y 158 -W 160 -ActionKey 'VoiceListen'
    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Cycle TTS' -X 176 -Y 158 -W 160 -ActionKey 'TtsCycle' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Tester IA (prompt)' -X 8 -Y 196 -W 160 -ActionKey 'AiTest' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Historique IA' -X 176 -Y 196 -W 160 -ActionKey 'AiHistory' | Out-Null

    # --- Fresh Windows ---
    $tabFw = New-FreshAgentDashboardTabPage -Title 'Fresh Windows' -TabControl $tabs
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Menu interactif (admin)' -X 8 -Y 12 -W 240 -ActionKey 'FwMenu' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Maintenance WinUtil' -X 8 -Y 50 -W 240 -ActionKey 'FwMaintenance' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Mode jeu (launcher admin)' -X 8 -Y 88 -W 240 -ActionKey 'FwGameMode' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Mettre a jour scripts locaux' -X 8 -Y 126 -W 240 -ActionKey 'SyncScripts' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'PowerShell (sans admin)' -X 8 -Y 164 -W 240 -ActionKey 'OpenPowerShell' | Out-Null

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
    $btnQuit.Tag = 'QuitAgent'
    $btnQuit.Add_Click({
            param($sender, $e)
            try {
                $map = $script:FreshAgentDashboardActions
                if (-not $map) { return }
                $sb = $map['QuitAgent']
                if ($sb -is [scriptblock]) { & $sb }
            }
            catch { }
        })
    $form.Controls.Add($btnQuit) | Out-Null

    $refreshTimer = New-Object System.Windows.Forms.Timer
    $refreshTimer.Interval = 4000
    $refreshTimer.Add_Tick({
            if ($form.IsDisposed) { return }
            try {
                if (-not $script:FreshAgentDashboardGetState) { return }
                $st = @{}
                try { $st = & $script:FreshAgentDashboardGetState } catch { $st = @{} }
                if (-not $st) { $st = @{} }
                Update-FreshAgentDashboardUi -Ui $script:FreshAgentDashboardUi -State $st
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

    Update-FreshAgentDashboardUi -Ui $ui -State (Get-FreshAgentDashboardStateSafe -GetState $GetState)
    [void]$form.Show($script:HiddenForm)
}

function Update-FreshAgentDashboardIfOpen {
    if (-not $script:FreshAgentDashboardForm -or $script:FreshAgentDashboardForm.IsDisposed) { return }
    if (-not $script:FreshAgentDashboardGetState) { return }
    try {
        Update-FreshAgentDashboardUi -Ui $script:FreshAgentDashboardUi -State (Get-FreshAgentDashboardStateSafe -GetState $script:FreshAgentDashboardGetState)
    }
    catch {
        try {
            Update-FreshAgentDashboardUi -Ui $script:FreshAgentDashboardUi -State (& $script:FreshAgentDashboardGetState)
        }
        catch { }
    }
}
