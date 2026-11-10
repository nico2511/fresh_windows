#Requires -Version 5.1

function Get-FreshAgentGameSessionStatePath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'game-session.state.json'
}

function Get-FreshAgentGameSessionState {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $path = Get-FreshAgentGameSessionStatePath -FreshAppData $FreshAppData
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { return $null }
}

function Set-FreshAgentGameSessionState {
    param(
        $State,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $path = Get-FreshAgentGameSessionStatePath -FreshAppData $FreshAppData
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Clear-FreshAgentGameSessionState {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $path = Get-FreshAgentGameSessionStatePath -FreshAppData $FreshAppData
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Get-WindowsFocusAssistSnapshot {
    $snap = @{
        pushToastEnabled = $null
        regPath          = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
        focusAssistType  = $null
        focusAssistPath  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\FocusAssist'
    }
    try {
        if (Test-Path -LiteralPath $snap.regPath) {
            $v = Get-ItemProperty -LiteralPath $snap.regPath -Name ToastEnabled -ErrorAction SilentlyContinue
            if ($null -ne $v.ToastEnabled) {
                $snap.pushToastEnabled = [int]$v.ToastEnabled
            }
        }
        if (Test-Path -LiteralPath $snap.focusAssistPath) {
            $fa = Get-ItemProperty -LiteralPath $snap.focusAssistPath -Name FocusAssistType -ErrorAction SilentlyContinue
            if ($null -ne $fa.FocusAssistType) {
                $snap.focusAssistType = [int]$fa.FocusAssistType
            }
        }
    }
    catch { }
    return $snap
}

function Set-WindowsFocusAssistBestEffort {
    param([switch]$Enable)
    $notes = @()
    $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
    try {
        if (-not (Test-Path -LiteralPath $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        if ($Enable) {
            Set-ItemProperty -LiteralPath $regPath -Name ToastEnabled -Value 0 -Type DWord -Force
            $notes += 'Toasts desactives (best-effort DND).'
            $faPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\FocusAssist'
            if (Test-Path -LiteralPath $faPath) {
                Set-ItemProperty -LiteralPath $faPath -Name FocusAssistType -Value 2 -Type DWord -Force
                $notes += 'Focus Assist: alarmes seulement (si cle supportee).'
            }
        }
        else {
            Set-ItemProperty -LiteralPath $regPath -Name ToastEnabled -Value 1 -Type DWord -Force
            $notes += 'Toasts reactives.'
        }
    }
    catch {
        $notes += "Focus Assist partiel: $($_.Exception.Message)"
    }
    return $notes
}

function Restore-WindowsFocusAssistSnapshot {
    param($Snapshot)
    if (-not $Snapshot) { return @('Aucun snapshot Focus Assist.') }
    $notes = @()
    try {
        if ($null -ne $Snapshot.pushToastEnabled) {
            $regPath = $Snapshot.regPath
            if (-not $regPath) { $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' }
            Set-ItemProperty -LiteralPath $regPath -Name ToastEnabled -Value ([int]$Snapshot.pushToastEnabled) -Type DWord -Force
            $notes += 'Toasts restaures depuis snapshot.'
        }
        if ($null -ne $Snapshot.focusAssistType) {
            $faPath = $Snapshot.focusAssistPath
            if (-not $faPath) { $faPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\FocusAssist' }
            if (Test-Path -LiteralPath $faPath) {
                Set-ItemProperty -LiteralPath $faPath -Name FocusAssistType -Value ([int]$Snapshot.focusAssistType) -Type DWord -Force
                $notes += 'Focus Assist restaure.'
            }
        }
    }
    catch {
        $notes += $_.Exception.Message
    }
    return $notes
}

function Get-ActivePowerSchemeGuid {
    try {
        $raw = powercfg /getactivescheme 2>&1 | Out-String
        if ($raw -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            return $Matches[1]
        }
    }
    catch { }
    return $null
}

function Set-ActivePowerSchemeGuid {
    param([string]$Guid)
    if ([string]::IsNullOrWhiteSpace($Guid)) { return $false }
    try {
        $null = powercfg /setactive $Guid 2>&1
        return $true
    }
    catch { return $false }
}
