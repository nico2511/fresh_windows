#Requires -Version 5.1
<#
  Journal des actions Fresh Agent (skills, confirmations, systeme).
#>

function Get-FreshAgentActionLogPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'action-log.jsonl'
}

function Add-FreshAgentActionLogEntry {
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$SkillId = '',
        [hashtable]$Parameters = @{},
        [bool]$Ok = $true,
        [string]$Message = '',
        [string]$Source = 'agent',
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [int]$MaxLines = 200
    )
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $path = Get-FreshAgentActionLogPath -FreshAppData $FreshAppData
    $entry = @{
        at         = (Get-Date).ToString('o')
        action     = $Action
        skillId    = $SkillId
        parameters = $Parameters
        ok         = $Ok
        message    = $Message
        source     = $Source
    } | ConvertTo-Json -Compress -Depth 6
    try {
        Add-Content -LiteralPath $path -Value $entry -Encoding UTF8
    }
    catch { return }

    try {
        $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
        if ($lines.Count -gt $MaxLines) {
            $lines = $lines[($lines.Count - $MaxLines)..($lines.Count - 1)]
            Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        }
    }
    catch { }
}

function Get-FreshAgentActionLogRecent {
    param(
        [int]$Count = 20,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $path = Get-FreshAgentActionLogPath -FreshAppData $FreshAppData
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
        $items = @()
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $items += ($line | ConvertFrom-Json) } catch { }
        }
        return @($items | Select-Object -Last $Count)
    }
    catch { return @() }
}
