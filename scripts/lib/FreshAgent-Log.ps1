#Requires -Version 5.1

function Get-FreshAgentLogPath {
    param(
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$Name = 'fresh-agent.log'
    )
    return Join-Path $FreshAppData $Name
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
