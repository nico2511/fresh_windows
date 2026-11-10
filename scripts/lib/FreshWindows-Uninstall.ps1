#Requires -Version 5.1
# Logique desinstallation Fresh Windows (importee par scripts/Uninstall-FreshWindows.ps1).
param(
    [switch]$DryRun,
    [switch]$ReinstallAfter,
    [switch]$Confirmed,
    [int[]]$ImmuneProcessIds = @(),
    [string]$ImmuneProcessIdsCsv = '',
    [string]$OwnedSessionId = '',
    [string]$SandboxLocalAppDataRoot = ''
)

$ErrorActionPreference = 'Continue'
$script:FreshUninstallSelfPid = $PID
$script:FreshUninstallRepoMainLauncher = 'https://raw.githubusercontent.com/nico2511/fresh_windows/main/launcher.ps1'
$script:FreshUninstallStepFailures = [System.Collections.ArrayList]@()
$script:FreshUninstallVerificationErrors = [System.Collections.ArrayList]@()
$script:FreshUninstallImmunePids = @{}
$script:FreshUninstallOwnedSessionId = if ($OwnedSessionId) { $OwnedSessionId } else { [guid]::NewGuid().ToString('N') }
$script:FreshUninstallOwnedReinstallStage = $null
$script:FreshUninstallOwnedRunScript = $null
$script:FreshUninstallFreshOwnershipMarker = '.fresh-windows-uninstall-owned'
$script:FreshUninstallTaskSnapshotOverride = $null
$script:FreshUninstallProcessEnumeratorOverride = $null

function Import-FreshUninstallImmuneIdsFromCsv {
    param([string]$Csv)
    if ([string]::IsNullOrWhiteSpace($Csv)) { return }
    foreach ($part in @($Csv.Split(','))) {
        $token = ([string]$part).Trim()
        if ($token -match '^\d+$') {
            $n = [int]$token
            if ($n -gt 0) { $script:FreshUninstallImmunePids[$n] = $true }
        }
    }
}

foreach ($imm in @($ImmuneProcessIds)) {
    if ($imm -gt 0) { $script:FreshUninstallImmunePids[[int]$imm] = $true }
}
Import-FreshUninstallImmuneIdsFromCsv -Csv $ImmuneProcessIdsCsv
$script:FreshUninstallImmunePids[[int]$PID] = $true

function Register-FreshUninstallImmuneProcessId {
    param([int]$ProcessId)
    if ($ProcessId -gt 0) { $script:FreshUninstallImmunePids[[int]$ProcessId] = $true }
}

function Get-FreshUninstallLocalRoot {
    if (-not [string]::IsNullOrWhiteSpace($SandboxLocalAppDataRoot)) {
        return (Join-Path $SandboxLocalAppDataRoot 'FreshWindows')
    }
    return (Join-Path $env:LOCALAPPDATA 'FreshWindows')
}

function Get-FreshUninstallLocalAppDataRoot {
    if (-not [string]::IsNullOrWhiteSpace($SandboxLocalAppDataRoot)) {
        return $SandboxLocalAppDataRoot
    }
    return $env:LOCALAPPDATA
}

function Test-FreshUninstallPathUnderRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $full = [System.IO.Path]::GetFullPath($Path.TrimEnd('\', '/'))
        $rootFull = [System.IO.Path]::GetFullPath($Root.TrimEnd('\', '/'))
    }
    catch { return $false }
    if ($full.Length -lt $rootFull.Length) { return $false }
    if ($full.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $sep = $full[$rootFull.Length]
    if ($sep -ne '\' -and $sep -ne '/') { return $false }
    return $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Get-FreshUninstallPowerShellScriptPathFromCommandLine {
    param([Parameter(Mandatory)][string]$CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    if ($CommandLine -match '(?:-File)\s+"([^"]+)"') { return $Matches[1] }
    if ($CommandLine -match "(?:-File)\s+(\S+)") { return $Matches[1] }
    return $null
}

function Test-FreshUninstallCommandTargetsFreshRoot {
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$FreshRoot
    )
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }
    $scriptPath = Get-FreshUninstallPowerShellScriptPathFromCommandLine -CommandLine $CommandLine
    if ($scriptPath) {
        try {
            $fullScript = [System.IO.Path]::GetFullPath($scriptPath)
        }
        catch { return $false }
        return (Test-FreshUninstallPathUnderRoot -Path $fullScript -Root $FreshRoot)
    }
    if ($CommandLine -match 'Start-WatchAgent\.cmd') {
        try {
            $rootFull = [System.IO.Path]::GetFullPath($FreshRoot.TrimEnd('\', '/'))
        }
        catch { return $false }
        $esc = [regex]::Escape($rootFull)
        return ($CommandLine -match "(?i)${esc}(\\|/|`"|'|\s|$)")
    }
    return $false
}

function Test-FreshUninstallProcessImmune {
    param(
        [int]$ProcessId,
        [string]$CommandLine = ''
    )
    if ($script:FreshUninstallImmunePids.ContainsKey([int]$ProcessId)) { return $true }
    if ($CommandLine -match 'Uninstall-FreshWindows|Launch-AfterUninstall') { return $true }
    return $false
}

function Add-FreshUninstallInspectionFailure {
    param([string]$Message)
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    [void]$script:FreshUninstallVerificationErrors.Add($Message)
}

function Test-FreshUninstallIsBenignProcessEnumerationError {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    if (-not $ErrorRecord) { return $false }
    $fqid = [string]$ErrorRecord.FullyQualifiedErrorId
    if ($fqid -like 'NoProcessFoundForGivenName*') { return $true }
    return $false
}

function Get-FreshUninstallProcessListByName {
    param([Parameter(Mandatory)][string]$Name)
    $nameErrors = $null
    $procList = @(Get-Process -Name $Name -ErrorAction SilentlyContinue -ErrorVariable nameErrors)
    foreach ($e in @($nameErrors)) {
        if (Test-FreshUninstallIsBenignProcessEnumerationError -ErrorRecord $e) { continue }
        Add-FreshUninstallInspectionFailure -Message ("enumeration processus {0} indisponible ({1})" -f $Name, $e.FullyQualifiedErrorId)
    }
    return $procList
}

function Get-FreshUninstallTargetProcesses {
    param([Parameter(Mandatory)][string]$FreshRoot)
    if ($script:FreshUninstallProcessEnumeratorOverride) {
        return [object[]](& $script:FreshUninstallProcessEnumeratorOverride)
    }
    $out = [System.Collections.ArrayList]@()
    $agentPattern = 'GameMode-WatchAgent|Launch-GameModeWatch|Start-WatchAgent\.cmd'
    $hostPattern = 'FreshAgent-VoiceHost'
    $launchPattern = 'Launch-GameModeKill\.ps1'

    foreach ($n in @('powershell', 'pwsh')) {
        $procList = @(Get-FreshUninstallProcessListByName -Name $n)
        if ($procList.Count -eq 0) { continue }
        foreach ($p in $procList) {
            $cmd = ''
            try {
                $cmd = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction Stop).CommandLine
            }
            catch {
                Add-FreshUninstallInspectionFailure -Message ("inspection CIM PID {0} impossible" -f $p.Id)
                continue
            }
            if (Test-FreshUninstallProcessImmune -ProcessId $p.Id -CommandLine $cmd) { continue }
            if (-not (Test-FreshUninstallCommandTargetsFreshRoot -CommandLine $cmd -FreshRoot $FreshRoot)) { continue }
            if ($cmd -match $agentPattern -or $cmd -match $hostPattern -or $cmd -match $launchPattern) {
                [void]$out.Add([pscustomobject]@{ ProcessId = $p.Id; Name = $p.ProcessName; CommandLine = $cmd })
            }
        }
    }

    $voiceList = @(Get-FreshUninstallProcessListByName -Name 'voice_worker')
    foreach ($p in $voiceList) {
        $path = ''
        try { $path = $p.Path } catch { }
        if (-not $path) {
            try {
                $path = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $p.Id) -ErrorAction Stop).ExecutablePath
            }
            catch {
                Add-FreshUninstallInspectionFailure -Message ("inspection voice_worker PID {0} impossible" -f $p.Id)
                continue
            }
        }
        try { $path = [System.IO.Path]::GetFullPath($path) } catch { continue }
        if (Test-FreshUninstallProcessImmune -ProcessId $p.Id -CommandLine $path) { continue }
        if (-not (Test-FreshUninstallPathUnderRoot -Path $path -Root (Join-Path $FreshRoot 'bin'))) { continue }
        [void]$out.Add([pscustomobject]@{ ProcessId = $p.Id; Name = $p.ProcessName; CommandLine = $path })
    }
    return [object[]]($out.ToArray())
}

function Add-FreshUninstallStepFailure {
    param([string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { return }
    [void]$script:FreshUninstallStepFailures.Add($Label)
}

function Invoke-FreshUninstallDoStep {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($DryRun) {
        Write-Host "[SIMULATION] $Label" -ForegroundColor Yellow
        return $true
    }
    try {
        & $Action
        Write-Host "[OK] $Label" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[ECHEC] $Label : $($_.Exception.Message)" -ForegroundColor Red
        Add-FreshUninstallStepFailure -Label $Label
        return $false
    }
}

function Test-FreshUninstallShortcutPointsToFreshInstall {
    param(
        [Parameter(Mandatory)][string]$LnkPath,
        [Parameter(Mandatory)][string]$FreshRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Target,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Arguments
    )
    if ([string]::IsNullOrWhiteSpace($Target)) { return $false }
    $name = [System.IO.Path]::GetFileName($LnkPath)
    if (Test-FreshUninstallPathUnderRoot -Path $Target -Root $FreshRoot) { return $true }
    try { $targetFull = [System.IO.Path]::GetFullPath($Target) } catch { $targetFull = $Target }
    if (Test-FreshUninstallPathUnderRoot -Path $targetFull -Root $FreshRoot) { return $true }
    if ($Target -match '\.cmd$' -and (Test-FreshUninstallPathUnderRoot -Path $targetFull -Root $FreshRoot)) { return $true }
    $psLine = ($Target + ' ' + $Arguments).Trim()
    $scriptPath = Get-FreshUninstallPowerShellScriptPathFromCommandLine -CommandLine $psLine
    if ($scriptPath) {
        try { $sp = [System.IO.Path]::GetFullPath($scriptPath) } catch { $sp = $scriptPath }
        if (Test-FreshUninstallPathUnderRoot -Path $sp -Root $FreshRoot) { return $true }
    }
    if ($name -eq 'Mode Jeu.lnk' -and $scriptPath -and ($scriptPath -match 'Launch-GameModeKill\.ps1$')) {
        try { $sp = [System.IO.Path]::GetFullPath($scriptPath) } catch { $sp = $scriptPath }
        return (Test-FreshUninstallPathUnderRoot -Path $sp -Root $FreshRoot)
    }
    if ($name -in @('Fresh Windows.lnk', 'FreshWindows.lnk')) {
        if ($scriptPath -and ($scriptPath -match 'Launch-FreshWindows\.ps1$')) {
            try { $sp = [System.IO.Path]::GetFullPath($scriptPath) } catch { $sp = $scriptPath }
            return (Test-FreshUninstallPathUnderRoot -Path $sp -Root $FreshRoot)
        }
        if ($Target -match 'powershell' -and (Test-FreshUninstallPathUnderRoot -Path $targetFull -Root $FreshRoot)) { return $true }
    }
    return $false
}

function Resolve-FreshUninstallShortcutOwnership {
    param(
        [Parameter(Mandatory)][string]$LnkPath,
        [Parameter(Mandatory)][string]$FreshRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Target,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Arguments
    )
    if ([string]::IsNullOrWhiteSpace($Target)) { return 'unknown' }
    if (Test-FreshUninstallShortcutPointsToFreshInstall -LnkPath $LnkPath -FreshRoot $FreshRoot -Target $Target -Arguments $Arguments) {
        return 'owned'
    }
    return 'foreign'
}

function Get-FreshUninstallShortcutOwnership {
    param(
        [Parameter(Mandatory)][string]$LnkPath,
        [Parameter(Mandatory)][string]$FreshRoot
    )
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $s = $wsh.CreateShortcut($LnkPath)
        $target = [string]$s.TargetPath
        $args = [string]$s.Arguments
        return (Resolve-FreshUninstallShortcutOwnership -LnkPath $LnkPath -FreshRoot $FreshRoot -Target $target -Arguments $args)
    }
    catch {
        return 'unknown'
    }
}

function Get-FreshUninstallDesktopShortcutInventory {
    param([Parameter(Mandatory)][string]$FreshRoot)
    $owned = [System.Collections.ArrayList]@()
    $foreign = [System.Collections.ArrayList]@()
    $unknown = [System.Collections.ArrayList]@()
    $names = @('Fresh Windows.lnk', 'FreshWindows.lnk', 'Mode Jeu.lnk')
    foreach ($root in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'))) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        foreach ($name in $names) {
            $p = Join-Path $root $name
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $own = Get-FreshUninstallShortcutOwnership -LnkPath $p -FreshRoot $FreshRoot
            switch ($own) {
                'owned' { [void]$owned.Add($p) }
                'foreign' { [void]$foreign.Add($p) }
                default { [void]$unknown.Add($p) }
            }
        }
    }
    return [pscustomobject]@{
        Owned   = @($owned)
        Foreign = @($foreign)
        Unknown = @($unknown)
    }
}

function Get-FreshUninstallTempTestDirInventory {
    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        return [pscustomobject]@{ Owned = @(); Unowned = @() }
    }
    $resolvedTemp = $null
    try { $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot) } catch {
        return [pscustomobject]@{ Owned = @(); Unowned = @() }
    }
    $owned = [System.Collections.ArrayList]@()
    $unowned = [System.Collections.ArrayList]@()
    foreach ($d in @(Get-ChildItem -LiteralPath $resolvedTemp -Directory -ErrorAction SilentlyContinue)) {
        if ($d.Name -notmatch '^fw-test') { continue }
        if (-not (Test-FreshUninstallPathUnderRoot -Path $d.FullName -Root $resolvedTemp)) { continue }
        $marker = Join-Path $d.FullName $script:FreshUninstallFreshOwnershipMarker
        if (Test-Path -LiteralPath $marker) { [void]$owned.Add($d.FullName) }
        else { [void]$unowned.Add($d.FullName) }
    }
    return [pscustomobject]@{ Owned = @($owned); Unowned = @($unowned) }
}

function Get-FreshUninstallScheduledTaskSnapshot {
    if ($script:FreshUninstallTaskSnapshotOverride) {
        return & $script:FreshUninstallTaskSnapshotOverride
    }
    $snapshot = [pscustomobject]@{
        Ok    = $false
        Tasks = @()
        Error = ''
    }
    try {
        if (-not (Get-Command Get-ScheduledTask -ErrorAction Stop)) {
            throw 'Get-ScheduledTask indisponible'
        }
        $list = [System.Collections.ArrayList]@()
        $all = Get-ScheduledTask -ErrorAction Stop
        foreach ($t in @($all)) {
            if ($t.TaskName -like 'FreshWindows-*') { [void]$list.Add($t) }
        }
        $snapshot.Ok = $true
        $snapshot.Tasks = @($list.ToArray())
        return $snapshot
    }
    catch {
        $snapshot.Error = $_.Exception.Message
        return $snapshot
    }
}

function Get-FreshUninstallVerification {
    param([Parameter(Mandatory)][string]$FreshRoot)
    $issues = [System.Collections.ArrayList]@()
    $warnings = [System.Collections.ArrayList]@()
    $unavailable = $false

    if (Test-Path -LiteralPath $FreshRoot) { [void]$issues.Add("Dossier encore present : $FreshRoot") }

    $taskSnap = Get-FreshUninstallScheduledTaskSnapshot
    if (-not $taskSnap.Ok) {
        $unavailable = $true
        [void]$issues.Add('verification taches planifiees indisponible')
        if ($taskSnap.Error) { [void]$issues.Add($taskSnap.Error) }
    }
    else {
        foreach ($t in @($taskSnap.Tasks)) { [void]$issues.Add("Tache encore presente : $($t.TaskName)") }
    }

    $shortcuts = Get-FreshUninstallDesktopShortcutInventory -FreshRoot $FreshRoot
    foreach ($lnk in @($shortcuts.Owned)) { [void]$issues.Add("Raccourci encore present : $lnk") }
    foreach ($lnk in @($shortcuts.Unknown)) {
        [void]$warnings.Add("Raccourci non attribuable (non supprime) : $lnk")
    }

    $tempInv = Get-FreshUninstallTempTestDirInventory
    foreach ($d in @($tempInv.Owned)) { [void]$issues.Add("Dossier temporaire encore present : $d") }
    foreach ($d in @($tempInv.Unowned)) {
        [void]$warnings.Add("Dossier fw-test sans marqueur Fresh (non supprime) : $d")
    }

    $processes = Get-FreshUninstallTargetProcesses -FreshRoot $FreshRoot
    foreach ($p in $processes) {
        if (-not $p -or $p.ProcessId -le 0) { continue }
        [void]$issues.Add("Processus encore actif : $($p.ProcessId) $($p.Name)")
    }

    if ($script:FreshUninstallVerificationErrors.Count -gt 0) {
        $unavailable = $true
        foreach ($e in $script:FreshUninstallVerificationErrors) { [void]$issues.Add($e) }
    }

    return [pscustomobject]@{
        Issues      = @($issues)
        Warnings    = @($warnings)
        Unavailable = $unavailable
    }
}

function Get-FreshUninstallReinstallStubContent {
    param([Parameter(Mandatory)][string]$MainUrl)
    return @"
#Requires -RunAsAdministrator
#Requires -Version 5.1
`$ErrorActionPreference = 'Stop'
`$launcher = '$MainUrl'
`$self = `$MyInvocation.MyCommand.Path
`$fresh = Join-Path `$env:LOCALAPPDATA 'FreshWindows'
`$deadline = (Get-Date).AddMinutes(8)
while ((Test-Path -LiteralPath `$fresh) -and (Get-Date) -lt `$deadline) {
    Start-Sleep -Seconds 2
}
function Remove-FreshUninstallReinstallStubStage {
    param([string]`$SelfPath)
    if ([string]::IsNullOrWhiteSpace(`$SelfPath)) { return }
    if (Test-Path -LiteralPath `$SelfPath) {
        try { Remove-Item -LiteralPath `$SelfPath -Force -ErrorAction Stop } catch {}
    }
    `$stageDir = Split-Path -Parent `$SelfPath
    if (`$stageDir -and (Test-Path -LiteralPath `$stageDir)) {
        try { Remove-Item -LiteralPath `$stageDir -Recurse -Force -ErrorAction Stop } catch {}
    }
}
if (Test-Path -LiteralPath `$fresh) {
    Write-Host ('Arret : dossier Fresh toujours present, relance annulee : ' + `$fresh) -ForegroundColor Red
    Remove-FreshUninstallReinstallStubStage -SelfPath `$self
    exit 3
}
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch {}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
`$env:FRESH_WIN_REF = 'main'
try {
    irm `$launcher | iex
    exit 0
}
catch {
    Write-Host ('Echec relance Fresh Windows (reseau ou acces) : ' + `$_.Exception.Message) -ForegroundColor Red
    Write-Host 'Relance manuelle (copier/coller dans PowerShell admin) :' -ForegroundColor Yellow
    Write-Host ('irm ' + `$launcher + ' | iex') -ForegroundColor Yellow
    exit 3
}
finally {
    Remove-FreshUninstallReinstallStubStage -SelfPath `$self
}
"@
}

function New-FreshUninstallReinstallStub {
    param([Parameter(Mandatory)][string]$MainUrl)
    $tempRoot = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempRoot)) { throw 'TEMP indisponible pour stub relance' }
    $stage = Join-Path $tempRoot ("FreshWindows-Reinstall-{0}" -f $script:FreshUninstallOwnedSessionId)
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $stubPath = Join-Path $stage 'Launch-AfterUninstall.ps1'
    $content = Get-FreshUninstallReinstallStubContent -MainUrl $MainUrl
    Set-Content -LiteralPath $stubPath -Value $content -Encoding UTF8 -ErrorAction Stop
    try { Unblock-File -LiteralPath $stubPath -ErrorAction SilentlyContinue } catch { }
    $script:FreshUninstallOwnedReinstallStage = $stage
    return $stubPath
}

function Start-FreshUninstallReinstallLauncher {
    param([Parameter(Mandatory)][string]$StubPath)
    if (-not (Test-Path -LiteralPath $StubPath)) {
        Write-Host "Stub relance introuvable : $StubPath" -ForegroundColor Red
        return $false
    }
    try {
        $p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$StubPath`"" `
            -WindowStyle Normal -PassThru -ErrorAction Stop
        if ($null -eq $p) {
            Write-Host 'Start-Process relance : aucun processus retourne.' -ForegroundColor Red
            return $false
        }
        Start-Sleep -Milliseconds 400
        if ($p.HasExited) {
            Write-Host ("Start-Process relance : processus termine immediatement (code {0})." -f $p.ExitCode) -ForegroundColor Red
            return $false
        }
        Write-Host 'Nettoyage reussi. Fenetre de relance demarree (succes reinstall non garanti).' -ForegroundColor Cyan
        return $true
    }
    catch {
        Write-Host "Impossible de demarrer la relance : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ('Relance manuelle : irm ' + $script:FreshUninstallRepoMainLauncher + ' | iex') -ForegroundColor Yellow
        return $false
    }
}

function Clear-FreshUninstallOwnedRunStagingOnly {
    if ($DryRun) { return $true }
    $ok = $true
    $tempRoot = $env:TEMP
    if (-not [string]::IsNullOrWhiteSpace($tempRoot) -and $script:FreshUninstallOwnedSessionId) {
        $runStage = Join-Path $tempRoot ("FreshWindows-UninstallRun-{0}" -f $script:FreshUninstallOwnedSessionId)
        if (Test-Path -LiteralPath $runStage) {
            try { Remove-Item -LiteralPath $runStage -Recurse -Force -ErrorAction Stop }
            catch { $ok = $false; Add-FreshUninstallStepFailure -Label 'Nettoyage staging UninstallRun proprietaire' }
        }
    }
    return $ok
}

function Clear-FreshUninstallOwnedStagingArtifacts {
    if ($DryRun) { return $true }
    $ok = $true
    $tempRoot = $env:TEMP
    if (-not (Clear-FreshUninstallOwnedRunStagingOnly)) { $ok = $false }
    if ($script:FreshUninstallOwnedReinstallStage -and (Test-Path -LiteralPath $script:FreshUninstallOwnedReinstallStage)) {
        try { Remove-Item -LiteralPath $script:FreshUninstallOwnedReinstallStage -Recurse -Force -ErrorAction Stop }
        catch { $ok = $false; Add-FreshUninstallStepFailure -Label 'Nettoyage staging relance proprietaire' }
    }
    return $ok
}

function Test-FreshUninstallElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal $id
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Invoke-FreshWindowsUninstall {
    $script:FreshUninstallStepFailures = [System.Collections.ArrayList]@()
    $script:FreshUninstallVerificationErrors = [System.Collections.ArrayList]@()

    if (-not $DryRun -and -not $Confirmed) {
        Write-Host "Annule : confirmation explicite requise (-Confirmed) ou utiliser -DryRun." -ForegroundColor Yellow
        return 2
    }

    if (-not $DryRun -and -not (Test-FreshUninstallElevated)) {
        Write-Host 'Acces refuse : PowerShell administrateur requis pour la suppression.' -ForegroundColor Red
        return 4
    }

    $localAppDataRoot = Get-FreshUninstallLocalAppDataRoot
    $freshExpected = Join-Path $localAppDataRoot 'FreshWindows'
    try { $freshCanonical = [System.IO.Path]::GetFullPath($freshExpected) }
    catch {
        Write-Host "Chemin Fresh Windows invalide." -ForegroundColor Red
        return 1
    }

    try { $localRoot = [System.IO.Path]::GetFullPath($localAppDataRoot) } catch { $localRoot = $null }
    if (-not $localRoot -or -not (Test-FreshUninstallPathUnderRoot -Path $freshCanonical -Root $localRoot)) {
        Write-Host "Refus : racine Fresh Windows hors LocalAppData attendu." -ForegroundColor Red
        return 1
    }

    Write-Host "`n=== Desinstallation Fresh Windows ===" -ForegroundColor Cyan
    if ($DryRun) { Write-Host "Mode simulation : aucune modification." -ForegroundColor Yellow }
    elseif ($ReinstallAfter) { Write-Host "Reinstall apres nettoyage : launcher main GitHub." -ForegroundColor DarkCyan }

    $targets = @(Get-FreshUninstallTargetProcesses -FreshRoot $freshCanonical | Where-Object { $_ -and $_.ProcessId -gt 0 })
    foreach ($p in $targets) {
        Invoke-FreshUninstallDoStep -Label "Arret du processus $($p.ProcessId) ($($p.Name))" -Action {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        } | Out-Null
    }

    $taskSnap = Get-FreshUninstallScheduledTaskSnapshot
    if (-not $taskSnap.Ok) {
        [void]$script:FreshUninstallVerificationErrors.Add('enumeration taches planifiees impossible')
        if ($taskSnap.Error) { [void]$script:FreshUninstallVerificationErrors.Add($taskSnap.Error) }
        if (-not $DryRun) { Add-FreshUninstallStepFailure -Label 'Lecture taches planifiees FreshWindows' }
    }
    elseif (@($taskSnap.Tasks).Count -gt 0) {
        foreach ($t in @($taskSnap.Tasks)) {
            Invoke-FreshUninstallDoStep -Label "Suppression de la tache $($t.TaskPath)$($t.TaskName)" -Action {
                Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            } | Out-Null
        }
    }

    $shortcuts = Get-FreshUninstallDesktopShortcutInventory -FreshRoot $freshCanonical
    foreach ($lnk in @($shortcuts.Foreign)) {
        Write-Host "[CONSERVE] Raccourci tiers homonyme : $lnk" -ForegroundColor DarkYellow
    }
    foreach ($lnk in @($shortcuts.Unknown)) {
        Write-Host "[SIGNALE] Raccourci non attribuable : $lnk" -ForegroundColor DarkYellow
    }
    foreach ($lnk in @($shortcuts.Owned)) {
        Invoke-FreshUninstallDoStep -Label "Suppression du raccourci $lnk" -Action {
            Remove-Item -LiteralPath $lnk -Force -ErrorAction Stop
        } | Out-Null
    }

    if (Test-Path -LiteralPath $freshCanonical) {
        if (-not $DryRun) { Start-Sleep -Seconds 2 }
        Invoke-FreshUninstallDoStep -Label "Suppression du dossier $freshCanonical" -Action {
            Remove-Item -LiteralPath $freshCanonical -Recurse -Force -ErrorAction Stop
        } | Out-Null
    }

    $tempInv = Get-FreshUninstallTempTestDirInventory
    foreach ($d in @($tempInv.Unowned)) {
        Write-Host "[SIGNALE] fw-test sans marqueur Fresh : $d" -ForegroundColor DarkYellow
    }
    foreach ($d in @($tempInv.Owned)) {
        Invoke-FreshUninstallDoStep -Label "Suppression du dossier temporaire $d" -Action {
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop
        } | Out-Null
    }

    Write-Host "`n--- Verification ---"
    if ($DryRun) {
        Write-Host "Simulation terminee, rien n'a ete supprime." -ForegroundColor Yellow
        return 0
    }

    if ($script:FreshUninstallStepFailures.Count -gt 0) {
        Write-Host "Echecs pendant le nettoyage :" -ForegroundColor Red
        $script:FreshUninstallStepFailures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host "Arret : pas de succes ni de relance tant que des etapes ont echoue." -ForegroundColor Red
        return 1
    }

    $verify = Get-FreshUninstallVerification -FreshRoot $freshCanonical
    if ($verify.Unavailable) {
        Write-Host "Verification incomplete (API indisponible) : pas de succes declare." -ForegroundColor Red
        $verify.Issues | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        return 1
    }
    foreach ($w in @($verify.Warnings)) { Write-Host $w -ForegroundColor DarkYellow }
    if ($verify.Issues.Count -gt 0) {
        $verify.Issues | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "Nettoyage incomplet : relance ou arret manuel requis." -ForegroundColor Red
        return 1
    }

    Write-Host "Fresh Windows est entierement supprime (cache local / agent / taches)." -ForegroundColor Green

    if ($ReinstallAfter) {
        try {
            $stub = New-FreshUninstallReinstallStub -MainUrl $script:FreshUninstallRepoMainLauncher
        }
        catch {
            Write-Host ("Creation stub relance impossible : {0}" -f $_.Exception.Message) -ForegroundColor Red
            return 3
        }
        $stubErrs = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($stub, [ref]$null, [ref]$stubErrs)
        if ($stubErrs -and $stubErrs.Count -gt 0) {
            Write-Host 'Stub relance invalide (parse) : reinstall annulee.' -ForegroundColor Red
            return 3
        }
        if (-not (Clear-FreshUninstallOwnedRunStagingOnly)) { return 1 }
        if (-not (Start-FreshUninstallReinstallLauncher -StubPath $stub)) {
            if (-not (Clear-FreshUninstallOwnedStagingArtifacts)) { return 1 }
            return 3
        }
        return 5
    }

    if (-not (Clear-FreshUninstallOwnedStagingArtifacts)) {
        Write-Host 'Nettoyage staging local incomplet.' -ForegroundColor Red
        return 1
    }
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = Invoke-FreshWindowsUninstall
    exit $exitCode
}
