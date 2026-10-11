#Requires -Version 5.1
<#
  Panneau Fresh Agent (clic gauche systray) — toggles et actions sans menu imbrique.
  Les handlers WinForms ne resolvent PAS Function: — uniquement $script: ScriptBlock.
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

# Log UI via $script: (jamais Function: depuis un handler WinForms).
$script:FreshAgentUiLog = {
    param([string]$Message)
    try {
        $root = $env:FRESH_WIN_APPDATA
        if ([string]::IsNullOrWhiteSpace($root)) {
            if ($script:FreshAppData) { $root = [string]$script:FreshAppData }
            else { $root = Join-Path $env:LOCALAPPDATA 'FreshWindows' }
        }
        $log = Join-Path $root 'watch-agent.log'
        $dir = Split-Path $log
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    catch { }
}

$script:FreshAgentDashboardUpdateUi = {
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
        if ($Ui.LblAiNotice -and $State.AiNotice) {
            $Ui.LblAiNotice.Text = [string]$State.AiNotice
        }
        if ($Ui.ChkAi) { $Ui.ChkAi.Enabled = [bool]$State.AiControlsEnabled }
        if ($Ui.ChkRag) { $Ui.ChkRag.Enabled = [bool]$State.AiControlsEnabled }
        if ($Ui.BtnListen) {
            $Ui.BtnListen.Enabled = [bool]$State.ListenEnabled
            if ($State.ListenButtonText) { $Ui.BtnListen.Text = [string]$State.ListenButtonText }
        }
        if ($Ui.BtnListenOff) {
            $Ui.BtnListenOff.Enabled = [bool]$State.ListenOffEnabled
        }
        if ($Ui.BtnListenMode) {
            $Ui.BtnListenMode.Enabled = [bool]$State.AiControlsEnabled
            if ($State.ListenModeButtonText) { $Ui.BtnListenMode.Text = [string]$State.ListenModeButtonText }
        }
        if ($Ui.BtnPttHotkey) {
            $Ui.BtnPttHotkey.Enabled = [bool]$State.AiControlsEnabled
            if ($State.PttHotkeyButtonText) { $Ui.BtnPttHotkey.Text = [string]$State.PttHotkeyButtonText }
        }
        foreach ($name in @('BtnStartOllama', 'BtnEnsureModel', 'BtnTtsCycle', 'BtnAiTest', 'BtnAiHistory', 'BtnCmdSend')) {
            if ($Ui[$name]) { $Ui[$name].Enabled = [bool]$State.AiControlsEnabled }
        }
        if ($Ui.TxtCmd) { $Ui.TxtCmd.Enabled = [bool]$State.AiControlsEnabled }
        if ($Ui.LblHealth -and $State.HealthSummary) {
            $Ui.LblHealth.Text = [string]$State.HealthSummary
        }
    }
    finally {
        $Ui._suppress = $false
    }
}

$script:FreshAgentDashboardGetStateSafe = {
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
        $log = $script:FreshAgentUiLog
        if ($log -is [scriptblock]) {
            & $log ("GetState safe: {0}" -f $_.Exception.ToString())
        }
        return @{}
    }
}

# Dispatcher publie sur $script: : les handlers WinForms ne resolvent pas Function:.
$script:FreshAgentDashboardRunTagged = {
    param(
        $Sender,
        [bool]$WithCheckedArg = $false
    )
    $key = ''
    $log = $script:FreshAgentUiLog
    try {
        if (-not $Sender) {
            if ($log -is [scriptblock]) { & $log 'Dashboard RunTagged: sender null' }
            return
        }
        $key = [string]$Sender.Tag
        if ([string]::IsNullOrWhiteSpace($key)) {
            if ($log -is [scriptblock]) { & $log 'Dashboard RunTagged: Tag vide' }
            return
        }
        if ($log -is [scriptblock]) {
            & $log ("Dashboard RunTagged begin key={0} checkedArg={1}" -f $key, $WithCheckedArg)
        }
        $map = $script:FreshAgentDashboardActions
        if (-not $map) {
            if ($log -is [scriptblock]) {
                & $log ("Dashboard RunTagged: Actions map null (key={0})" -f $key)
            }
            return
        }
        $mapCount = @($map.Keys).Count
        $sb = $map[$key]
        if (-not ($sb -is [scriptblock])) {
            if ($log -is [scriptblock]) {
                & $log ("Dashboard RunTagged: pas de scriptblock pour key={0} (map keys={1})" -f $key, $mapCount)
            }
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
        if ($log -is [scriptblock]) {
            & $log ("Dashboard RunTagged OK key={0}" -f $key)
        }
    }
    catch {
        $msg = $_.Exception.ToString()
        if ($log -is [scriptblock]) {
            & $log ("Dashboard RunTagged FAIL key={0}: {1}" -f $key, $msg)
        }
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

$script:FreshAgentDashboardClickHandler = {
    param(
        $Sender,
        [string]$Source = 'control'
    )
    $log = $script:FreshAgentUiLog
    if ($log -is [scriptblock]) {
        & $log ("Dashboard click begin ({0})" -f $Source)
    }
    try {
        $run = $script:FreshAgentDashboardRunTagged
        if (-not ($run -is [scriptblock])) {
            if ($log -is [scriptblock]) {
                & $log ("Dashboard click: RunTagged absent ({0})" -f $Source)
            }
            return
        }
        $withChecked = ($Sender -is [System.Windows.Forms.CheckBox])
        & $run $Sender $withChecked
    }
    catch {
        if ($log -is [scriptblock]) {
            & $log ("Dashboard click error ({0}): {1}" -f $Source, $_.Exception.ToString())
        }
    }
    if ($log -is [scriptblock]) {
        & $log ("Dashboard click end ({0})" -f $Source)
    }
}

function Write-FreshAgentUiLog {
    param([string]$Message)
    $sb = $script:FreshAgentUiLog
    if ($sb -is [scriptblock]) { & $sb $Message }
}

function Invoke-FreshAgentDashboardClickHandler {
    param(
        $Sender,
        [string]$Source = 'control'
    )
    $sb = $script:FreshAgentDashboardClickHandler
    if ($sb -is [scriptblock]) { & $sb $Sender $Source }
}

function Update-FreshAgentDashboardUi {
    param(
        [hashtable]$Ui,
        [hashtable]$State
    )
    $sb = $script:FreshAgentDashboardUpdateUi
    if ($sb -is [scriptblock]) { & $sb $Ui $State }
}

function Get-FreshAgentDashboardStateSafe {
    param($GetState)
    $sb = $script:FreshAgentDashboardGetStateSafe
    if ($sb -is [scriptblock]) { return & $sb $GetState }
    return @{}
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
            $h = $script:FreshAgentDashboardClickHandler
            if ($h -is [scriptblock]) {
                & $h $sender ('btn:' + [string]$sender.Tag)
            }
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
            $h = $script:FreshAgentDashboardClickHandler
            if ($h -is [scriptblock]) {
                & $h $sender ('chk:' + [string]$sender.Tag)
            }
        })
    $Parent.Controls.Add($cb) | Out-Null
    return $cb
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
    $log = $script:FreshAgentUiLog
    if ($log -is [scriptblock]) {
        & $log ("Show-FreshAgentDashboard: {0} actions enregistrees [{1}]" -f @($Actions.Keys).Count, $actionKeys)
    }

    $getSafe = $script:FreshAgentDashboardGetStateSafe
    $upd = $script:FreshAgentDashboardUpdateUi

    if ($script:FreshAgentDashboardForm -and -not $script:FreshAgentDashboardForm.IsDisposed) {
        $st = if ($getSafe -is [scriptblock]) { & $getSafe $GetState } else { @{} }
        if ($upd -is [scriptblock]) { & $upd $script:FreshAgentDashboardUi $st }
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
    $form.ClientSize = New-Object System.Drawing.Size(540, 460)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 251)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.AutoSize = $false
    $lblStatus.Location = New-Object System.Drawing.Point(16, 10)
    $lblStatus.Size = New-Object System.Drawing.Size(508, 32)
    $lblStatus.Text = 'Fresh Agent'
    $lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($lblStatus) | Out-Null

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(16, 48)
    $tabs.Size = New-Object System.Drawing.Size(508, 350)
    $form.Controls.Add($tabs) | Out-Null

    $ui = @{
        LblStatus = $lblStatus
        _suppress = $false
    }

    # --- Jeu ---
    $tabGame = New-FreshAgentDashboardTabPage -Title 'Jeu' -TabControl $tabs
    $ui.ChkAuto = Add-FreshAgentDashboardCheck -Parent $tabGame -Text 'Detection auto (suggestions kill)' -X 12 -Y 16 -ActionKey 'ToggleAutoSuggest'
    $ui.ChkMon = Add-FreshAgentDashboardCheck -Parent $tabGame -Text 'Surveillance CPU / alertes' -X 12 -Y 48 -ActionKey 'ToggleMonitor'
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Mode jeu (liste + launchers)' -X 12 -Y 96 -W 460 -H 36 -ActionKey 'GameModeKill' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Fermer launchers inactifs' -X 12 -Y 142 -W 460 -H 36 -ActionKey 'IdleLaunchers' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabGame -Text 'Tuer suggestions en attente' -X 12 -Y 188 -W 460 -H 36 -ActionKey 'PendingKill' | Out-Null

    # --- Skills & profils ---
    $tabSkills = New-FreshAgentDashboardTabPage -Title 'Skills' -TabControl $tabs
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Jeu' -X 12 -Y 16 -W 148 -H 34 -ActionKey 'ProfileGame' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Travail' -X 168 -Y 16 -W 148 -H 34 -ActionKey 'ProfileWork' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Profil Clean' -X 324 -Y 16 -W 148 -H 34 -ActionKey 'ProfileClean' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Etat systeme' -X 12 -Y 68 -W 460 -H 34 -ActionKey 'SkillHealth' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Session jeu (DND)' -X 12 -Y 112 -W 226 -H 34 -ActionKey 'SkillGameSession' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabSkills -Text 'Fin session jeu' -X 246 -Y 112 -W 226 -H 34 -ActionKey 'SkillEndGame' | Out-Null

    # --- IA / Voix ---
    $tabAi = New-FreshAgentDashboardTabPage -Title 'IA' -TabControl $tabs
    $ui.LblAiNotice = New-Object System.Windows.Forms.Label
    $ui.LblAiNotice.AutoSize = $false
    $ui.LblAiNotice.Location = New-Object System.Drawing.Point(12, 8)
    $ui.LblAiNotice.Size = New-Object System.Drawing.Size(460, 28)
    $ui.LblAiNotice.Text = 'Commande texte = meme routeur que la voix (Ollama en secours).'
    $tabAi.Controls.Add($ui.LblAiNotice) | Out-Null

    $ui.TxtCmd = New-Object System.Windows.Forms.TextBox
    $ui.TxtCmd.Location = New-Object System.Drawing.Point(12, 40)
    $ui.TxtCmd.Size = New-Object System.Drawing.Size(340, 24)
    $ui.TxtCmd.Tag = 'TxtCmd'
    $tabAi.Controls.Add($ui.TxtCmd) | Out-Null
    $ui.BtnCmdSend = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Envoyer' -X 360 -Y 38 -W 112 -H 28 -ActionKey 'SubmitTextCommand'

    $ui.ChkAi = Add-FreshAgentDashboardCheck -Parent $tabAi -Text 'Intelligence artificielle (Ollama)' -X 12 -Y 76 -ActionKey 'SetAiEnabled'
    $ui.ChkRag = Add-FreshAgentDashboardCheck -Parent $tabAi -Text 'RAG guides Fresh Windows' -X 12 -Y 104 -ActionKey 'SetRagEnabled'
    $ui.LblOllama = New-Object System.Windows.Forms.Label
    $ui.LblOllama.AutoSize = $true
    $ui.LblOllama.Location = New-Object System.Drawing.Point(12, 136)
    $ui.LblOllama.Text = 'Ollama : ?'
    $tabAi.Controls.Add($ui.LblOllama) | Out-Null
    $ui.LblStt = New-Object System.Windows.Forms.Label
    $ui.LblStt.AutoSize = $true
    $ui.LblStt.Location = New-Object System.Drawing.Point(12, 158)
    $ui.LblStt.Text = 'STT : off'
    $tabAi.Controls.Add($ui.LblStt) | Out-Null

    $ui.BtnListenMode = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Mode : Appui maintenu' -X 12 -Y 186 -W 226 -H 28 -ActionKey 'ListenModeCycle'
    $ui.BtnPttHotkey = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Raccourci PTT : Ctrl+Alt+Space' -X 246 -Y 186 -W 226 -H 28 -ActionKey 'PttHotkeyPick'
    $ui.BtnListen = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Ecoute ON' -X 12 -Y 220 -W 226 -H 32 -ActionKey 'VoiceListenOn'
    $ui.BtnListenOff = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Ecoute OFF' -X 246 -Y 220 -W 226 -H 32 -ActionKey 'VoiceListenOff'
    $ui.BtnStartOllama = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Demarrer Ollama' -X 12 -Y 260 -W 148 -H 30 -ActionKey 'StartOllama'
    $ui.BtnEnsureModel = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Modele' -X 168 -Y 260 -W 100 -H 30 -ActionKey 'EnsureModel'
    $ui.BtnTtsCycle = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Cycle TTS' -X 276 -Y 260 -W 100 -H 30 -ActionKey 'TtsCycle'
    $ui.BtnAiTest = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Tester IA' -X 12 -Y 298 -W 110 -H 30 -ActionKey 'AiTest'
    $ui.BtnAiHistory = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Historique' -X 130 -Y 298 -W 110 -H 30 -ActionKey 'AiHistory'
    $ui.BtnCmdHelp = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Aide cmds' -X 248 -Y 298 -W 110 -H 30 -ActionKey 'VoiceCommandsHelp'
    $ui.BtnAppInv = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Apps/alias' -X 366 -Y 298 -W 106 -H 30 -ActionKey 'AppInventoryHelp'
    # Note: bouton Apps/alias = inventaire Start Menu + aliases (ex: discord -> Legcord)

    # --- Sante ---
    $tabHealth = New-FreshAgentDashboardTabPage -Title 'Sante' -TabControl $tabs
    $ui.LblHealth = New-Object System.Windows.Forms.Label
    $ui.LblHealth.AutoSize = $false
    $ui.LblHealth.Location = New-Object System.Drawing.Point(12, 16)
    $ui.LblHealth.Size = New-Object System.Drawing.Size(460, 120)
    $ui.LblHealth.Text = 'CPU / RAM / disque — actualisation automatique.'
    $tabHealth.Controls.Add($ui.LblHealth) | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabHealth -Text 'Rafraichir sante' -X 12 -Y 150 -W 226 -H 34 -ActionKey 'RefreshHealth' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabHealth -Text 'Rapport hebdo' -X 246 -Y 150 -W 226 -H 34 -ActionKey 'WeeklyReport' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabHealth -Text 'Audit demarrage' -X 12 -Y 196 -W 226 -H 34 -ActionKey 'AuditStartup' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabHealth -Text 'Audit services' -X 246 -Y 196 -W 226 -H 34 -ActionKey 'AuditServices' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabHealth -Text 'Nettoyage (confirm)' -X 12 -Y 242 -W 460 -H 34 -ActionKey 'CleanupConfirm' | Out-Null

    # --- Fresh Windows ---
    $tabFw = New-FreshAgentDashboardTabPage -Title 'Fresh Windows' -TabControl $tabs
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Menu interactif (admin)' -X 12 -Y 16 -W 460 -H 36 -ActionKey 'FwMenu' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Maintenance WinUtil' -X 12 -Y 62 -W 460 -H 36 -ActionKey 'FwMaintenance' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Mode jeu (launcher admin)' -X 12 -Y 108 -W 460 -H 36 -ActionKey 'FwGameMode' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'Mettre a jour scripts locaux' -X 12 -Y 154 -W 460 -H 36 -ActionKey 'SyncScripts' | Out-Null
    Add-FreshAgentDashboardButton -Parent $tabFw -Text 'PowerShell (sans admin)' -X 12 -Y 200 -W 460 -H 36 -ActionKey 'OpenPowerShell' | Out-Null

    $script:FreshAgentDashboardForm = $form
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Fermer'
    $btnClose.Location = New-Object System.Drawing.Point(348, 412)
    $btnClose.Size = New-Object System.Drawing.Size(84, 30)
    $btnClose.Add_Click({
            $f = $script:FreshAgentDashboardForm
            if ($f -and -not $f.IsDisposed) { $f.Hide() }
        })
    $form.Controls.Add($btnClose) | Out-Null
    $form.Add_FormClosing({
            param($sender, $e)
            if ($script:WatchAgentExitRequested) { return }
            $e.Cancel = $true
            if ($sender -and -not $sender.IsDisposed) { $sender.Hide() }
        })

    $btnQuit = New-Object System.Windows.Forms.Button
    $btnQuit.Text = 'Quitter agent'
    $btnQuit.Location = New-Object System.Drawing.Point(440, 412)
    $btnQuit.Size = New-Object System.Drawing.Size(84, 30)
    $btnQuit.Tag = 'QuitAgent'
    $btnQuit.Add_Click({
            param($sender, $e)
            $h = $script:FreshAgentDashboardClickHandler
            if ($h -is [scriptblock]) {
                & $h $sender 'btn:QuitAgent'
            }
        })
    $form.Controls.Add($btnQuit) | Out-Null

    $refreshTimer = New-Object System.Windows.Forms.Timer
    $refreshTimer.Interval = 4000
    $refreshTimer.Add_Tick({
            if ($form.IsDisposed) { return }
            try {
                if (-not $script:FreshAgentDashboardGetState) { return }
                $getSafe = $script:FreshAgentDashboardGetStateSafe
                $upd = $script:FreshAgentDashboardUpdateUi
                $st = @{}
                if ($getSafe -is [scriptblock]) {
                    $st = & $getSafe $script:FreshAgentDashboardGetState
                }
                if (-not $st) { $st = @{} }
                if ($upd -is [scriptblock]) {
                    & $upd $script:FreshAgentDashboardUi $st
                }
            }
            catch {
                $log = $script:FreshAgentUiLog
                if ($log -is [scriptblock]) {
                    & $log ("Dashboard refresh tick: {0}" -f $_.Exception.ToString())
                }
            }
        })
    $refreshTimer.Start()
    $form.Add_FormClosed({
            $refreshTimer.Stop()
            $refreshTimer.Dispose()
        })

    $script:FreshAgentDashboardForm = $form
    $script:FreshAgentDashboardUi = $ui

    $st0 = if ($getSafe -is [scriptblock]) { & $getSafe $GetState } else { @{} }
    if ($upd -is [scriptblock]) { & $upd $ui $st0 }
    [void]$form.Show($script:HiddenForm)
}

function Update-FreshAgentDashboardIfOpen {
    if (-not $script:FreshAgentDashboardForm -or $script:FreshAgentDashboardForm.IsDisposed) { return }
    if (-not $script:FreshAgentDashboardGetState) { return }
    try {
        $getSafe = $script:FreshAgentDashboardGetStateSafe
        $upd = $script:FreshAgentDashboardUpdateUi
        $st = if ($getSafe -is [scriptblock]) { & $getSafe $script:FreshAgentDashboardGetState } else { @{} }
        if ($upd -is [scriptblock]) { & $upd $script:FreshAgentDashboardUi $st }
    }
    catch {
        try {
            $upd = $script:FreshAgentDashboardUpdateUi
            if ($upd -is [scriptblock]) {
                & $upd $script:FreshAgentDashboardUi (& $script:FreshAgentDashboardGetState)
            }
        }
        catch { }
    }
}
