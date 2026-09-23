#Requires -Version 5.1

function Get-FreshAgentAiHistoryPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'ai-history.jsonl'
}

function Add-FreshAgentAiHistoryEntry {
    param(
        [string]$Prompt,
        [string]$Response,
        [string[]]$Skills = @(),
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [int]$MaxLines = 80
    )
    if ([string]::IsNullOrWhiteSpace($Prompt)) { return }
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $path = Get-FreshAgentAiHistoryPath -FreshAppData $FreshAppData
    $entry = @{
        at       = (Get-Date).ToString('o')
        prompt   = $Prompt
        response = $Response
        skills   = @($Skills)
    } | ConvertTo-Json -Compress
    Add-Content -LiteralPath $path -Value $entry -Encoding UTF8

    try {
        $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
        if ($lines.Count -gt $MaxLines) {
            $lines = $lines[($lines.Count - $MaxLines)..($lines.Count - 1)]
            Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
        }
    }
    catch { }
}

function Get-FreshAgentAiHistoryRecent {
    param(
        [int]$Count = 5,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $path = Get-FreshAgentAiHistoryPath -FreshAppData $FreshAppData
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
