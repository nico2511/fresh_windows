#Requires -Version 5.1
<#
  Taches IA / Ollama en arriere-plan (appele avec powershell -File uniquement).
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('StartOllama', 'EnsureModel')]
    [string]$Action,
    [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'),
    [string]$RepoRef = 'main'
)

function Get-FreshAgentBgRepoRef {
    param(
        [string]$FreshAppData,
        [string]$RepoRef
    )
    if (-not [string]::IsNullOrWhiteSpace($RepoRef)) {
        return $RepoRef.Trim()
    }
    if ($env:FRESH_WIN_REF) {
        return $env:FRESH_WIN_REF.Trim()
    }
    $refFile = Join-Path $FreshAppData 'scripts.ref'
    if (Test-Path -LiteralPath $refFile) {
        try {
            return (Get-Content -LiteralPath $refFile -Raw -Encoding UTF8).Trim()
        }
        catch { }
    }
    return 'main'
}

function Resolve-FreshAgentBgScriptPath {
    param(
        [string]$FreshAppData,
        [string]$RelativePath,
        [string]$RepoRef
    )
    $rel = $RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    $local = Join-Path $FreshAppData $rel
    if (Test-Path -LiteralPath $local) {
        return $local
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch { }
    $raw = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/scripts/$($RelativePath -replace '\\', '/')"
    $dir = Split-Path $local -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    try {
        Invoke-WebRequest -Uri $raw -OutFile $local -UseBasicParsing
        if (Test-Path -LiteralPath $local) {
            return $local
        }
    }
    catch { }
    return $null
}

function Invoke-FreshAgentBackgroundWorkerMain {
    param(
        [string]$Action,
        [string]$FreshAppData,
        [string]$RepoRef
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
    $ref = Get-FreshAgentBgRepoRef -FreshAppData $FreshAppData

    try {
        $configPath = Resolve-FreshAgentBgScriptPath -FreshAppData $FreshAppData -RelativePath 'lib/FreshAgent-Config.ps1' -RepoRef $ref
        $ollamaPath = Resolve-FreshAgentBgScriptPath -FreshAppData $FreshAppData -RelativePath 'ai/Ollama-Manager.ps1' -RepoRef $ref
        if (-not $configPath) {
            throw "FreshAgent-Config introuvable sous $FreshAppData\lib — sync scripts locaux (menu Fresh Windows)."
        }
        if (-not $ollamaPath) {
            throw "Ollama-Manager introuvable sous $FreshAppData\ai — sync scripts locaux."
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
            $cfg = Get-FreshAgentAiConfig -RepoRef $ref -FreshAppData $FreshAppData
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
}

# Ne pas executer le worker si le fichier est dot-source (sync / import module).
$inv = $MyInvocation
$dotSourced = ($null -ne $inv.InvocationName -and $inv.InvocationName -eq '.') `
    -or ($null -ne $inv.Line -and $inv.Line -match '(?m)^\s*\.\s')

if (-not $dotSourced) {
    Invoke-FreshAgentBackgroundWorkerMain -Action $Action -FreshAppData $FreshAppData -RepoRef $RepoRef
}
