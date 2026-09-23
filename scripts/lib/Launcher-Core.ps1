#Requires -Version 5.1
<#
  Fonctions partagées Fresh Windows (launcher irm, clone local, tâches planifiées).
  Dot-sourcé depuis launcher.ps1 - utilise $RepoRef, $RepoRawRoot, $LauncherUrl, $FreshAppData du parent.
#>

function Wait-ForUser {
    if ($Host.Name -eq 'ConsoleHost') {
        Read-Host "`nEntrée pour continuer"
    }
}

function Get-WingetUpgradePowerShellCommand {
    return 'winget source update --disable-interactivity; winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity'
}

function Invoke-WingetUpgradeAll {
    param([switch]$NoPause)

    $ok = $true
    winget source update --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Échec winget source update (code $LASTEXITCODE)" -ForegroundColor Red
        $ok = $false
    }
    winget upgrade --all --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Échec / partiel winget upgrade (code $LASTEXITCODE)" -ForegroundColor Red
        $ok = $false
    }
    elseif ($ok) {
        Write-Host "winget upgrade terminé." -ForegroundColor Green
    }
    if (-not $NoPause) { Wait-ForUser }
    return $ok
}

function Get-FreshWindowsLaunchStubContent {
    param(
        [string]$Ref,
        [string]$LauncherUrl
    )
    return @"
#Requires -RunAsAdministrator
param([string]`$SilentMode = '')
`$ErrorActionPreference = 'Stop'
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch {}
try {
    `$cu = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
    if (`$cu -in @('Restricted', 'AllSigned')) {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue
    }
} catch {}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
`$env:FRESH_WIN_REF = '$Ref'
if (`$SilentMode) { `$env:FRESH_WIN_MODE = `$SilentMode.Trim().ToLowerInvariant() }
irm '$LauncherUrl' | iex
"@
}

function Write-FreshWindowsLaunchStub {
    param(
        [string]$FreshAppData,
        [string]$Ref,
        [string]$LauncherUrl
    )
    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $stubPath = Join-Path $FreshAppData "Launch-FreshWindows.ps1"
    Set-Content -LiteralPath $stubPath -Value (Get-FreshWindowsLaunchStubContent -Ref $Ref -LauncherUrl $LauncherUrl) -Encoding UTF8
    try { Unblock-File -LiteralPath $stubPath -ErrorAction SilentlyContinue } catch { }
    return $stubPath
}

function Start-FreshWindowsUnelevated {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$WorkingDirectory = ''
    )

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = Split-Path -Parent $FilePath
    }

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'powershell' -and $_.CommandLine -match 'GameMode-WatchAgent|Launch-GameModeWatch|Start-WatchAgent' } |
        ForEach-Object {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }

    $cmdPath = Join-Path $WorkingDirectory 'Start-WatchAgent.cmd'
    if (-not (Test-Path -LiteralPath $cmdPath)) {
        throw "Start-WatchAgent.cmd introuvable (menu 11 d'abord)."
    }

    # Un seul argument : le .cmd (pas de quotes PowerShell imbriquees)
    Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" `
        -ArgumentList "/trustlevel:0x20000 `"$cmdPath`"" `
        -WorkingDirectory $WorkingDirectory
    Start-Sleep -Seconds 1

    $alive = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'Launch-GameModeWatch|GameMode-WatchAgent|Start-WatchAgent' }
    if (-not $alive) {
        Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList "`"$cmdPath`""
    }
}

function Test-FreshWindowsIsElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal $id
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Register-FreshWindowsWatchAgentLogon {
    <#
      Tache AtLogOn Limited. Depuis un launcher admin, Register-ScheduledTask -Force
      renvoie souvent Acces refuse : on enregistre via runas trustlevel (non eleve).
    #>
    param(
        [Parameter(Mandatory)][string]$FreshAppData
    )

    $taskName = 'FreshWindows-WatchAgent'
    $cmdPath = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
    if (-not (Test-Path -LiteralPath $cmdPath)) {
        throw "Start-WatchAgent.cmd introuvable."
    }

    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        foreach ($a in @($existing.Actions)) {
            $exe = [string]$a.Execute
            if ($exe -and ($exe -eq $cmdPath -or $exe -like '*Start-WatchAgent.cmd*')) {
                return $taskName
            }
        }
    }

    $helperPs1 = Join-Path $FreshAppData 'Register-WatchAgentTask.ps1'
    $helperCmd = Join-Path $FreshAppData 'Register-WatchAgentTask.cmd'
    @"
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$taskName = 'FreshWindows-WatchAgent'
`$dir = if (`$PSScriptRoot) { `$PSScriptRoot } else { Split-Path -Parent `$MyInvocation.MyCommand.Path }
`$cmdPath = Join-Path `$dir 'Start-WatchAgent.cmd'
Unregister-ScheduledTask -TaskName `$taskName -Confirm:`$false -ErrorAction SilentlyContinue
`$action = New-ScheduledTaskAction -Execute `$cmdPath -WorkingDirectory `$dir
`$trigger = New-ScheduledTaskTrigger -AtLogOn -User `$env:USERNAME
`$trigger.Delay = 'PT45S'
`$principal = New-ScheduledTaskPrincipal -UserId `$env:USERNAME -LogonType Interactive -RunLevel Limited
`$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -DontStopOnIdleEnd
Register-ScheduledTask -TaskName `$taskName -Action `$action -Trigger `$trigger -Principal `$principal -Settings `$settings -Description 'Fresh Windows agent tray (Limited).' -Force | Out-Null
"@ | Set-Content -LiteralPath $helperPs1 -Encoding UTF8

    @"
@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Register-WatchAgentTask.ps1"
"@ | Set-Content -LiteralPath $helperCmd -Encoding ASCII

    if (-not (Test-FreshWindowsIsElevated)) {
        & $helperPs1
        return $taskName
    }

    Start-Process -FilePath "$env:SystemRoot\System32\runas.exe" `
        -ArgumentList "/trustlevel:0x20000 `"$helperCmd`"" `
        -Wait -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 800

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        return $taskName
    }

    $null = & "$env:SystemRoot\System32\schtasks.exe" /Delete /TN $taskName /F 2>&1
    $create = & "$env:SystemRoot\System32\schtasks.exe" /Create /TN $taskName /TR "`"$cmdPath`"" /SC ONLOGON /RL LIMITED /F 2>&1
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        return $taskName
    }

    throw ("Acces refuse pour la tache Limited. Startup .lnk reste actif. Detail: {0}" -f ($create | Out-String).Trim())
}

function Sync-GameModeLocalScripts {
    param(
        [string]$FreshAppData,
        [string]$RepoRawRoot,
        [string]$Ref,
        [string]$IconUrl = ''
    )

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null

    if ($IconUrl) {
        $iconPath = Join-Path $FreshAppData "fresh-windows.ico"
        if (-not (Test-Path -LiteralPath $iconPath)) {
            try { Invoke-WebRequest -Uri $IconUrl -OutFile $iconPath -UseBasicParsing } catch { }
        }
    }

    foreach ($scriptName in @('GameMode-Common.ps1', 'Invoke-GameModeKill.ps1', 'GameMode-WatchAgent.ps1', 'Sync-FreshWindowsAgent.ps1')) {
        $dest = Join-Path $FreshAppData $scriptName
        $url  = "$RepoRawRoot/scripts/$scriptName"
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        if (Get-Command Set-FreshScriptUtf8Bom -ErrorAction SilentlyContinue) {
            Set-FreshScriptUtf8Bom -Path $dest
        }
        Write-Host "-> $scriptName" -ForegroundColor DarkGray
    }

    $configLib = Join-Path $FreshAppData 'lib\FreshAgent-Config.ps1'
    $configLibUrl = "$RepoRawRoot/scripts/lib/FreshAgent-Config.ps1"
    try {
        $libDir = Split-Path $configLib -Parent
        if (-not (Test-Path -LiteralPath $libDir)) { New-Item -ItemType Directory -Path $libDir -Force | Out-Null }
        Invoke-WebRequest -Uri $configLibUrl -OutFile $configLib -UseBasicParsing
        . $configLib
        Sync-FreshAgentLocalAssets -FreshAppData $FreshAppData -RepoRawRoot $RepoRawRoot -Ref $Ref | Out-Null
    }
    catch {
        Write-Host "!! Sync Fresh Agent partiel : $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Set-Content -LiteralPath (Join-Path $FreshAppData 'scripts.ref') -Value $Ref -Encoding UTF8 -NoNewline

    $killStub = Join-Path $FreshAppData "Launch-GameModeKill.ps1"
    @"
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$dir = if (`$PSScriptRoot) { `$PSScriptRoot } else { Split-Path -Parent `$MyInvocation.MyCommand.Path }
`$refFile = Join-Path `$dir 'scripts.ref'
`$ref = if (`$env:FRESH_WIN_REF) { `$env:FRESH_WIN_REF.Trim() } elseif (Test-Path -LiteralPath `$refFile) { (Get-Content -LiteralPath `$refFile -Raw).Trim() } else { 'main' }
`$env:FRESH_WIN_REF = `$ref
`$env:FRESH_WIN_NO_PAUSE = '1'
`$need = @('GameMode-Common.ps1', 'Invoke-GameModeKill.ps1')
foreach (`$n in `$need) {
    `$p = Join-Path `$dir `$n
    if (-not (Test-Path -LiteralPath `$p) -or ((Get-Item -LiteralPath `$p).Length -lt 80)) {
        Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/nico2511/fresh_windows/`$ref/scripts/`$n") -OutFile `$p -UseBasicParsing
    }
}
& (Join-Path `$dir 'Invoke-GameModeKill.ps1')
"@ | Set-Content -LiteralPath $killStub -Encoding UTF8

    $watchStub = Join-Path $FreshAppData "Launch-GameModeWatch.ps1"
    @"
#Requires -Version 5.1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
`$ErrorActionPreference = 'Continue'
`$dir = if (`$PSScriptRoot) { `$PSScriptRoot } else { Split-Path -Parent `$MyInvocation.MyCommand.Path }
`$log = Join-Path `$dir 'watch-agent.log'
function Write-WatchBootLog([string]`$Message) {
    try { Add-Content -LiteralPath `$log -Value ((Get-Date -Format o) + ' ' + `$Message) -Encoding UTF8 } catch { }
}
Write-WatchBootLog 'stub start'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }
`$refFile = Join-Path `$dir 'scripts.ref'
`$ref = if (`$env:FRESH_WIN_REF) { `$env:FRESH_WIN_REF.Trim() } elseif (Test-Path -LiteralPath `$refFile) { (Get-Content -LiteralPath `$refFile -Raw).Trim() } else { 'main' }
`$env:FRESH_WIN_REF = `$ref
`$need = @('GameMode-Common.ps1', 'GameMode-WatchAgent.ps1')
foreach (`$n in `$need) {
    `$p = Join-Path `$dir `$n
    if (-not (Test-Path -LiteralPath `$p) -or ((Get-Item -LiteralPath `$p).Length -lt 80)) {
        Write-WatchBootLog ("re-download `$n (ref `$ref)")
        Invoke-WebRequest -Uri ("https://raw.githubusercontent.com/nico2511/fresh_windows/`$ref/scripts/`$n") -OutFile `$p -UseBasicParsing
    }
}
Write-WatchBootLog 'WatchAgent invoke start'
try {
    & (Join-Path `$dir 'GameMode-WatchAgent.ps1')
    Write-WatchBootLog 'WatchAgent invoke end (exit normal)'
}
catch {
    Write-WatchBootLog ('WatchAgent invoke erreur: ' + (`$_ | Out-String))
    throw
}
"@ | Set-Content -LiteralPath $watchStub -Encoding UTF8

    # start /min : le dossier Startup ne reste pas bloque sur Application.Run
    $cmdPath = Join-Path $FreshAppData 'Start-WatchAgent.cmd'
    @"
@echo off
cd /d "%~dp0"
echo %DATE% %TIME% cmd start>> "%~dp0watch-agent.log"
if not exist "%~dp0Launch-GameModeWatch.ps1" (
  echo %DATE% %TIME% missing stub - abort>> "%~dp0watch-agent.log"
  exit /b 1
)
start "FreshWindowsWatch" /MIN "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch-GameModeWatch.ps1"
exit /b 0
"@ | Set-Content -LiteralPath $cmdPath -Encoding ASCII

    return $true
}
