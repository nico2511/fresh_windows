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
        $log = Join-Path $env:LOCALAPPDATA 'FreshWindows\watch-agent.log'
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
        foreach ($name in @('BtnStartOllama', 'BtnEnsureModel', 'BtnTtsCycle', 'BtnAiTest', 'BtnAiHistory')) {
            if ($Ui[$name]) { $Ui[$name].Enabled = [bool]$State.AiControlsEnabled }
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
    $ui.LblAiNotice.Location = New-Object System.Drawing.Point(12, 12)
    $ui.LblAiNotice.Size = New-Object System.Drawing.Size(460, 48)
    $ui.LblAiNotice.Text = 'Voix / IA : chantier en reconstruction. Core mode jeu et skills restent actifs.'
    $tabAi.Controls.Add($ui.LblAiNotice) | Out-Null
    $ui.ChkAi = Add-FreshAgentDashboardCheck -Parent $tabAi -Text 'Intelligence artificielle (Ollama)' -X 12 -Y 68 -ActionKey 'SetAiEnabled'
    $ui.ChkRag = Add-FreshAgentDashboardCheck -Parent $tabAi -Text 'RAG guides Fresh Windows' -X 12 -Y 100 -ActionKey 'SetRagEnabled'
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

    $ui.BtnListen = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Ecoute ON' -X 12 -Y 190 -W 226 -H 34 -ActionKey 'VoiceListenOn'
    $ui.BtnListenOff = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Ecoute OFF' -X 246 -Y 190 -W 226 -H 34 -ActionKey 'VoiceListenOff'
    $ui.BtnStartOllama = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Demarrer Ollama' -X 12 -Y 234 -W 148 -H 32 -ActionKey 'StartOllama'
    $ui.BtnEnsureModel = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Modele' -X 168 -Y 234 -W 100 -H 32 -ActionKey 'EnsureModel'
    $ui.BtnTtsCycle = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Cycle TTS' -X 276 -Y 234 -W 100 -H 32 -ActionKey 'TtsCycle'
    $ui.BtnAiTest = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Tester IA' -X 12 -Y 276 -W 226 -H 32 -ActionKey 'AiTest'
    $ui.BtnAiHistory = Add-FreshAgentDashboardButton -Parent $tabAi -Text 'Historique' -X 246 -Y 276 -W 226 -H 32 -ActionKey 'AiHistory'

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
