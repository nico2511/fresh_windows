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

function Get-OllamaAppExecutable {
    # App tray Windows (icone) — distinct de ollama.exe CLI/serve.
    $list = [System.Collections.Generic.List[string]]::new()
    $cli = Get-OllamaExecutable
    if ($cli) {
        $dir = Split-Path $cli -Parent
        [void]$list.Add((Join-Path $dir 'ollama app.exe'))
    }
    [void]$list.Add((Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'))
    [void]$list.Add((Join-Path $env:ProgramFiles 'Ollama\ollama app.exe'))
    foreach ($p in $list) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
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
        [int]$TimeoutSec = 2
    )
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        $BaseUrl = 'http://127.0.0.1:11434'
    }
    $BaseUrl = $BaseUrl.Trim().TrimEnd('/')
    # localhost peut resoudre en IPv6 (::1) alors qu'Ollama ecoute en IPv4.
    if ($BaseUrl -match '(?i)^https?://localhost(?::|/|$)') {
        $BaseUrl = $BaseUrl -replace '(?i)^(https?://)localhost', '${1}127.0.0.1'
    }
    $uri = "$BaseUrl/api/tags"
    try {
        $null = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec $TimeoutSec
        return $true
    }
    catch {
        try {
            $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec $TimeoutSec
            return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 300)
        }
        catch {
            return $false
        }
    }
}

function Start-OllamaServer {
    param(
        [string]$OllamaExe = $(Get-OllamaExecutable),
        [switch]$PreferTrayApp
    )
    if (-not $PSBoundParameters.ContainsKey('PreferTrayApp')) {
        $PreferTrayApp = $true
    }
    if (-not $OllamaExe) {
        throw 'Ollama introuvable. Installe-le (winget install Ollama.Ollama) ou ajoute ollama au PATH.'
    }

    $appExe = Get-OllamaAppExecutable
    $apiOk = Test-OllamaApi
    $appRunning = $false
    try {
        $appRunning = [bool](Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)^ollama' -and $_.CommandLine -and $_.CommandLine -match '(?i)ollama app\.exe' } |
                Select-Object -First 1)
    }
    catch { }

    # Preferer l'app tray (icone) plutot que "ollama serve" cache.
    if ($PreferTrayApp -and $appExe) {
        if (-not $appRunning) {
            Start-Process -FilePath $appExe | Out-Null
        }
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 800
            if (Test-OllamaApi) {
                return @{
                    alreadyRunning = $apiOk
                    exe            = $appExe
                    mode           = 'tray'
                }
            }
        }
        # API pas encore up: tenter serve en secours (API seule, sans promettre l'icone)
    }

    if (Test-OllamaApi) {
        return @{ alreadyRunning = $true; exe = $OllamaExe; mode = 'api' }
    }

    $existing = Get-Process -Name ollama -ErrorAction SilentlyContinue
    if (-not $existing) {
        Start-Process -FilePath $OllamaExe -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
    }
    else {
        Start-Process -FilePath $OllamaExe -ArgumentList 'serve' -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    }

    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 800
        if (Test-OllamaApi) {
            return @{ alreadyRunning = $false; exe = $OllamaExe; mode = 'serve' }
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
        [scriptblock]$OnProgress,
        [switch]$SkipPull
    )
    $base = Get-OllamaBaseUrl -AiConfig $AiConfig
    $ollama = $AiConfig.ollama
    $autoStart = $true
    if ($null -ne $ollama.autoStart) { $autoStart = [bool]$ollama.autoStart }

    if (-not (Test-OllamaApi -BaseUrl $base -TimeoutSec 2)) {
        if (-not $autoStart) {
            throw 'Ollama API injoignable et autoStart desactive.'
        }
        if ($OnProgress) { & $OnProgress 'Demarrage Ollama...' }
        Start-OllamaServer | Out-Null
    }

    $model = Resolve-OllamaChatModel -AiConfig $AiConfig -BaseUrl $base
    if ([string]::IsNullOrWhiteSpace($model)) { $model = 'qwen2.5:7b' }

    $pull = $true
    if ($null -ne $ollama.pullOnEnable) { $pull = [bool]$ollama.pullOnEnable }
    if ($SkipPull) { $pull = $false }

    if (-not (Test-OllamaModelPresent -ModelName $model -BaseUrl $base)) {
        if ($pull) {
            if ($OnProgress) { & $OnProgress "Telechargement modele $model..." }
            Invoke-OllamaPullModel -ModelName $model -OnLine {
                param($line)
                if ($OnProgress) { & $OnProgress $line }
            }
            if (-not (Test-OllamaModelPresent -ModelName $model -BaseUrl $base)) {
                throw ("Modele Ollama toujours absent apres pull: {0}" -f $model)
            }
        }
        else {
            throw ("Modele Ollama absent: {0}. Active l'IA (pullOnEnable) ou Telecharge le modele." -f $model)
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
    $resp = Invoke-OllamaChatCompletion -AiConfig $AiConfig -Messages @(
        @{ role = 'user'; content = $Prompt }
    ) -Tools @() -TimeoutSec $TimeoutSec
    if (-not $resp.ok) { return $resp.message }
    if ($resp.message -and $resp.message.content) {
        return $resp.message.content
    }
    return ($resp.raw | ConvertTo-Json -Compress)
}

function Resolve-OllamaChatModel {
    param($AiConfig, [string]$BaseUrl)
    $wanted = @()
    if ($AiConfig -and $AiConfig.ollama -and $AiConfig.ollama.defaultModel) {
        $wanted += [string]$AiConfig.ollama.defaultModel
    }
    if ($AiConfig -and $AiConfig.ollama -and $AiConfig.ollama.models) {
        foreach ($m in @($AiConfig.ollama.models)) {
            if ($m -and ($wanted -notcontains [string]$m)) { $wanted += [string]$m }
        }
    }
    $installed = @()
    try {
        $resp = Invoke-RestMethod -Uri "$BaseUrl/api/tags" -Method Get -TimeoutSec 5
        foreach ($m in @($resp.models)) {
            if ($m.name) { $installed += [string]$m.name }
        }
    }
    catch { }
    foreach ($w in $wanted) {
        if ($installed -contains $w) { return $w }
    }
    # Prefixe family (qwen2.5:3b -> qwen2.5:7b)
    foreach ($w in $wanted) {
        $family = ($w -split ':')[0]
        $pat = "${family}:*"
        $hit = $installed | Where-Object { $_ -like $pat } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    if ($installed.Count -gt 0) { return $installed[0] }
    if ($wanted.Count -gt 0) { return $wanted[0] }
    return 'qwen2.5:7b'
}

function Invoke-OllamaChatCompletion {
    param(
        $AiConfig,
        [array]$Messages,
        [array]$Tools = @(),
        [int]$TimeoutSec = 120
    )
    $base = Get-OllamaBaseUrl -AiConfig $AiConfig
    $model = Resolve-OllamaChatModel -AiConfig $AiConfig -BaseUrl $base
    $bodyObj = @{
        model    = $model
        messages = @($Messages)
        stream   = $false
    }
    if ($Tools -and $Tools.Count -gt 0) {
        $bodyObj.tools = @($Tools)
    }
    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    try {
        $raw = Invoke-RestMethod -Uri "$base/api/chat" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec $TimeoutSec
        return @{
            ok      = $true
            message = $raw.message
            raw     = $raw
            model   = $model
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match '404') {
            $msg = "Modele Ollama introuvable ($model). Installe-le (ollama pull $model) ou change defaultModel."
        }
        return @{
            ok      = $false
            message = $msg
            model   = $model
        }
    }
}
