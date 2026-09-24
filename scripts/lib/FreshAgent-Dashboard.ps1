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

function Write-FreshAgentUiLog {
    param([string]$Message)
    try {
        if (Get-Command Write-WatchLog -ErrorAction SilentlyContinue) {
            Write-WatchLog $Message
        }
    }
    catch { }
}

function Invoke-FreshAgentDashboardClickHandler {
    param(
        $Sender,
        [string]$Source = 'control'
    )
    Write-FreshAgentUiLog ("Dashboard click begin ({0})" -f $Source)
    try {
        $run = $script:FreshAgentDashboardRunTagged
        if (-not ($run -is [scriptblock])) {
            Write-FreshAgentUiLog ("Dashboard click: RunTagged absent ({0})" -f $Source)
            return
        }
        $withChecked = ($Sender -is [System.Windows.Forms.CheckBox])
        & $run $Sender $withChecked
    }
    catch {
        Write-FreshAgentUiLog ("Dashboard click error ({0}): {1}" -f $Source, $_.Exception.ToString())
    }
    Write-FreshAgentUiLog ("Dashboard click end ({0})" -f $Source)
}

# Dispatcher publie sur $script: : les handlers WinForms ne resolvent pas Function:.
$script:FreshAgentDashboardRunTagged = {
    param(
        $Sender,
        [bool]$WithCheckedArg = $false
    )
    $key = ''
    try {
        if (-not $Sender) {
            Write-FreshAgentUiLog 'Dashboard RunTagged: sender null'
            return
        }
        $key = [string]$Sender.Tag
        if ([string]::IsNullOrWhiteSpace($key)) {
            Write-FreshAgentUiLog 'Dashboard RunTagged: Tag vide'
            return
        }
        Write-FreshAgentUiLog ("Dashboard RunTagged begin key={0} checkedArg={1}" -f $key, $WithCheckedArg)
        $map = $script:FreshAgentDashboardActions
        if (-not $map) {
            Write-FreshAgentUiLog ("Dashboard RunTagged: Actions map null (key={0})" -f $key)
            return
        }
        $mapCount = @($map.Keys).Count
        $sb = $map[$key]
        if (-not ($sb -is [scriptblock])) {
            Write-FreshAgentUiLog ("Dashboard RunTagged: pas de scriptblock pour key={0} (map keys={1})" -f $key, $mapCount)
            return
        }

        $invokeArgs = @()
        if ($WithCheckedArg) {
            $invokeArgs = @([bool]$Sender.Checked)
        }

        $ss = $script:WatchAgentSessionState
        if ($ss) {
            $null = $ss.InvokeCommand.InvokeScript($false, $sb, $null, $invokeArgs)
        }
        else {
            if ($invokeArgs.Count -gt 0) { & $sb @invokeArgs } else { & $sb }
        }
        Write-FreshAgentUiLog ("Dashboard RunTagged OK key={0}" -f $key)
    }
    catch {
        $msg = $_.Exception.ToString()
        Write-FreshAgentUiLog ("Dashboard RunTagged FAIL key={0}: {1}" -f $key, $msg)
        try {
            [System.Windows.Forms.MessageBox]::Show(
                ("Action '{0}' : {1}" -f $key, $_.Exception.Message),
                'Fresh Agent',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
        catch { }
    }
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
            Invoke-FreshAgentDashboardClickHandler -Sender $sender -Source ('btn:' + [string]$sender.Tag)
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
            if ($script:FreshAgentDashboardUi -and $script:FreshAgentDashboardUi._suppress) { return }
            Invoke-FreshAgentDashboardClickHandler -Sender $sender -Source ('chk:' + [string]$sender.Tag)
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
    try {
        $ss = $script:WatchAgentSessionState
        if ($ss) {
            return $ss.InvokeCommand.InvokeScript($false, $sb, $null, @())
        }
        return & $sb
    }
    catch {
        Write-FreshAgentUiLog ("GetState safe: {0}" -f $_.Exception.ToString())
        return @{}
    }
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
    $actionKeys = @($Actions.Keys) -join ','
    Write-FreshAgentUiLog ("Show-FreshAgentDashboard: {0} actions enregistrees [{1}]" -f @($Actions.Keys).Count, $actionKeys)

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
            Invoke-FreshAgentDashboardClickHandler -Sender $sender -Source 'btn:QuitAgent'
        })
    $form.Controls.Add($btnQuit) | Out-Null

    $refreshTimer = New-Object System.Windows.Forms.Timer
    $refreshTimer.Interval = 4000
    $refreshTimer.Add_Tick({
            if ($form.IsDisposed) { return }
            try {
                if (-not $script:FreshAgentDashboardGetState) { return }
                $st = Get-FreshAgentDashboardStateSafe -GetState $script:FreshAgentDashboardGetState
                if (-not $st) { $st = @{} }
                Update-FreshAgentDashboardUi -Ui $script:FreshAgentDashboardUi -State $st
            }
            catch {
                Write-FreshAgentUiLog ("Dashboard refresh tick: {0}" -f $_.Exception.ToString())
            }
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
