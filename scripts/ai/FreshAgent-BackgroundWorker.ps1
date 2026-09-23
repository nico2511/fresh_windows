#Requires -Version 5.1
<#
  Taches IA / Ollama en arriere-plan (appele par GameMode-WatchAgent.ps1).
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('StartOllama', 'EnsureModel')]
    [string]$Action,
    [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'),
    [string]$RepoRef = 'main'
)

$ErrorActionPreference = 'Continue'
$resultPath = Join-Path $FreshAppData 'fa-bg-result.json'
$logPath = Join-Path $FreshAppData 'watch-agent.log'

function Write-BgLog {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $logPath -Value ('{0} BG {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
    }
    catch { }
}

function Write-BgResult {
    param(
        [bool]$Ok,
        [string]$Message,
        [string]$ActionName
    )
    $payload = @{
        ok      = $Ok
        message = $Message
        action  = $ActionName
        at      = (Get-Date).ToString('o')
    }
    try {
        New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
        $payload | ConvertTo-Json -Compress | Set-Content -LiteralPath $resultPath -Encoding UTF8
    }
    catch {
        Write-BgLog ("Result write failed: {0}" -f $_.Exception.Message)
    }
}

$ok = $false
$message = 'Erreur inconnue.'

try {
    $configPath = Join-Path $FreshAppData 'lib\FreshAgent-Config.ps1'
    $ollamaPath = Join-Path $FreshAppData 'ai\Ollama-Manager.ps1'
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "FreshAgent-Config absent: $configPath — sync scripts locaux."
    }
    if (-not (Test-Path -LiteralPath $ollamaPath)) {
        throw "Ollama-Manager absent: $ollamaPath — sync scripts locaux."
    }
    . $configPath
    . $ollamaPath

    if ($Action -eq 'StartOllama') {
        Write-BgLog 'Start-OllamaServer...'
        $started = Start-OllamaServer
        $ok = $true
        if ($started.alreadyRunning) {
            $message = 'Ollama deja actif (API OK).'
        }
        else {
            $message = 'Ollama demarre — API disponible.'
        }
    }
    else {
        Write-BgLog 'Ensure-OllamaReady...'
        $cfg = Get-FreshAgentAiConfig -RepoRef $RepoRef -FreshAppData $FreshAppData
        Ensure-OllamaReady -AiConfig $cfg -OnProgress { param($m) Write-BgLog $m } | Out-Null
        $model = if ($cfg.ollama.defaultModel) { $cfg.ollama.defaultModel } else { 'qwen2.5:3b' }
        $ok = $true
        $message = "Ollama pret — modele $model disponible."
    }
}
catch {
    $message = $_.Exception.Message
    Write-BgLog $message
}

Write-BgResult -Ok $ok -Message $message -ActionName $Action
if (-not $ok) {
    exit 1
}
