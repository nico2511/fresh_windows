#Requires -Version 5.1

function Get-FreshAgentLogPath {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$Name = 'fresh-agent.log'
    )
    return Join-Path $FreshAppData $Name
}

function Get-FreshAgentLogTranscriptsEnabled {
    param([string]$FreshAppData)
    if ([string]::IsNullOrWhiteSpace($FreshAppData)) {
        if (Get-Command Get-FreshAgentAppDataRoot -ErrorAction SilentlyContinue) {
            $FreshAppData = Get-FreshAgentAppDataRoot
        }
        elseif ($env:FRESH_WIN_APPDATA -and -not [string]::IsNullOrWhiteSpace($env:FRESH_WIN_APPDATA)) {
            $FreshAppData = $env:FRESH_WIN_APPDATA.Trim()
        }
        else {
            $FreshAppData = Join-Path $env:LOCALAPPDATA 'FreshWindows'
        }
    }
    foreach ($path in @(
            (Join-Path $FreshAppData 'watch-agent-user.json'),
            (Join-Path $FreshAppData 'agent-ai.user.json')
        )) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $u = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $u.logTranscripts) { return [bool]$u.logTranscripts }
            if ($u.stt -and $null -ne $u.stt.logTranscripts) { return [bool]$u.stt.logTranscripts }
        }
        catch { }
    }
    return $false
}

function Get-FreshAgentTranscriptSha256Prefix8 {
    param([string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        if ($sha -is [IDisposable]) { $sha.Dispose() }
    }
    return (-join ($hash[0..3] | ForEach-Object { $_.ToString('x2') }))
}

function Format-FreshAgentTranscriptForLog {
    <#
      Par defaut : longueur + 8 premiers hex du SHA-256 (UTF-8).
      Texte en clair si logTranscripts=true dans watch-agent-user.json ou agent-ai.user.json.
    #>
    param(
        [string]$Text,
        [string]$FreshAppData
    )
    if ($null -eq $Text) { $Text = '' }
    if (Get-FreshAgentLogTranscriptsEnabled -FreshAppData $FreshAppData) {
        return $Text
    }
    $len = $Text.Length
    if ($len -eq 0) { return 'len=0' }
    $fp = Get-FreshAgentTranscriptSha256Prefix8 -Text $Text
    return ('len={0} sha256={1}' -f $len, $fp)
}

function Write-FreshAgentLog {
    param(
        [string]$Category = 'Core',
        [string]$Message,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [int]$MaxBytes = 2097152
    )
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    $path = Get-FreshAgentLogPath -FreshAppData $FreshAppData
    try {
        $dir = Split-Path $path -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Length -gt $MaxBytes)) {
            $bak = "$path.bak"
            if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force }
            Move-Item -LiteralPath $path -Destination $bak -Force
        }
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Category, $Message
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    }
    catch { }
}
