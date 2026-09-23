#Requires -Version 5.1
<#
  Demarrage Ollama + verification / telechargement des modeles (API locale).
#>

function Get-OllamaExecutable {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        (Join-Path $env:ProgramFiles 'Ollama\ollama.exe')
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-OllamaBaseUrl {
    param($AiConfig)
    if ($AiConfig -and $AiConfig.ollama -and $AiConfig.ollama.baseUrl) {
        return $AiConfig.ollama.baseUrl.Trim().TrimEnd('/')
    }
    return 'http://127.0.0.1:11434'
}

function Test-OllamaApi {
    param(
        [string]$BaseUrl = 'http://127.0.0.1:11434',
        [int]$TimeoutSec = 3
    )
    try {
        $null = Invoke-RestMethod -Uri "$BaseUrl/api/tags" -Method Get -TimeoutSec $TimeoutSec
        return $true
    }
    catch {
        return $false
    }
}

function Start-OllamaServer {
    param(
        [string]$OllamaExe = $(Get-OllamaExecutable)
    )
    if (-not $OllamaExe) {
        throw 'Ollama introuvable. Installe-le (winget install Ollama.Ollama) ou ajoute ollama au PATH.'
    }
    if (Test-OllamaApi) { return @{ alreadyRunning = $true; exe = $OllamaExe } }

    $existing = Get-Process -Name ollama -ErrorAction SilentlyContinue
    if (-not $existing) {
        Start-Process -FilePath $OllamaExe -ArgumentList 'serve' -WindowStyle Hidden
    }

    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 800
        if (Test-OllamaApi) {
            return @{ alreadyRunning = $false; exe = $OllamaExe }
        }
    }
    throw 'Ollama ne repond pas sur http://127.0.0.1:11434 apres demarrage.'
}

function Get-OllamaLocalModels {
    param([string]$BaseUrl = 'http://127.0.0.1:11434')
    try {
        $resp = Invoke-RestMethod -Uri "$BaseUrl/api/tags" -Method Get -TimeoutSec 15
        $names = @()
        foreach ($m in @($resp.models)) {
            if ($m.name) { $names += $m.name }
        }
        return $names
    }
    catch {
        return @()
    }
}

function Test-OllamaModelPresent {
    param(
        [string]$ModelName,
        [string]$BaseUrl = 'http://127.0.0.1:11434'
    )
    if ([string]::IsNullOrWhiteSpace($ModelName)) { return $false }
    $want = $ModelName.Trim().ToLowerInvariant()
    foreach ($n in (Get-OllamaLocalModels -BaseUrl $BaseUrl)) {
        if ($n.ToLowerInvariant() -eq $want) { return $true }
        if ($n.ToLowerInvariant().StartsWith($want + ':')) { return $true }
        if ($want.Contains(':') -and $n.ToLowerInvariant().StartsWith($want.Split(':')[0] + ':')) { return $true }
    }
    return $false
}

function Invoke-OllamaPullModel {
    param(
        [Parameter(Mandatory)]
        [string]$ModelName,
        [string]$OllamaExe = $(Get-OllamaExecutable),
        [scriptblock]$OnLine
    )
    if (-not $OllamaExe) { throw 'Ollama introuvable.' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $OllamaExe
    $psi.Arguments = "pull $ModelName"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    while (-not $p.StandardOutput.EndOfStream) {
        $line = $p.StandardOutput.ReadLine()
        if ($OnLine -and $line) { & $OnLine $line }
    }
    while (-not $p.StandardError.EndOfStream) {
        $line = $p.StandardError.ReadLine()
        if ($OnLine -and $line) { & $OnLine $line }
    }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        throw "ollama pull $ModelName a echoue (code $($p.ExitCode))."
    }
}

function Ensure-OllamaReady {
    param(
        $AiConfig,
        [scriptblock]$OnProgress
    )
    $base = Get-OllamaBaseUrl -AiConfig $AiConfig
    $ollama = $AiConfig.ollama
    $autoStart = $true
    if ($null -ne $ollama.autoStart) { $autoStart = [bool]$ollama.autoStart }

    if (-not (Test-OllamaApi -BaseUrl $base)) {
        if (-not $autoStart) {
            throw 'Ollama API injoignable et autoStart desactive.'
        }
        if ($OnProgress) { & $OnProgress 'Demarrage Ollama...' }
        Start-OllamaServer | Out-Null
    }

    $model = [string]$ollama.defaultModel
    if ([string]::IsNullOrWhiteSpace($model)) { $model = 'qwen2.5:3b' }

    $pull = $true
    if ($null -ne $ollama.pullOnEnable) { $pull = [bool]$ollama.pullOnEnable }

    if ($pull -and -not (Test-OllamaModelPresent -ModelName $model -BaseUrl $base)) {
        if ($OnProgress) { & $OnProgress "Telechargement modele $model..." }
        Invoke-OllamaPullModel -ModelName $model -OnLine {
            param($line)
            if ($OnProgress) { & $OnProgress $line }
        }
    }

    return @{
        baseUrl = $base
        model   = $model
        ok      = $true
    }
}

function Invoke-OllamaChat {
    param(
        [string]$Prompt,
        $AiConfig,
        [int]$TimeoutSec = 120
    )
    $base = Get-OllamaBaseUrl -AiConfig $AiConfig
    $model = $AiConfig.ollama.defaultModel
    $body = @{
        model    = $model
        messages = @(
            @{ role = 'user'; content = $Prompt }
        )
        stream   = $false
    } | ConvertTo-Json -Depth 6
    $resp = Invoke-RestMethod -Uri "$base/api/chat" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $TimeoutSec
    if ($resp.message -and $resp.message.content) {
        return $resp.message.content
    }
    return ($resp | ConvertTo-Json -Compress)
}
