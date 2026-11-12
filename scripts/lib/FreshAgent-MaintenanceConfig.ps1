#Requires -Version 5.1
<#
  Sync maintenance agent (systray) vers %LOCALAPPDATA%\FreshWindows — sans IA/voix.
#>

function Get-FreshAgentAppDataRoot {
    if ($env:FRESH_WIN_APPDATA -and -not [string]::IsNullOrWhiteSpace($env:FRESH_WIN_APPDATA)) {
        return $env:FRESH_WIN_APPDATA.Trim()
    }
    if ($script:FreshAppData -and -not [string]::IsNullOrWhiteSpace([string]$script:FreshAppData)) {
        return [string]$script:FreshAppData
    }
    return Join-Path $env:LOCALAPPDATA 'FreshWindows'
}

function Set-FreshScriptUtf8Bom {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return }
        $needsBom = $false
        foreach ($b in $bytes) { if ($b -gt 127) { $needsBom = $true; break } }
        if (-not $needsBom) { return }
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $text = $utf8NoBom.GetString($bytes)
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($Path, $text, $utf8Bom)
    }
    catch { }
}
