#Requires -Version 5.1
<#
  Nettoyage des applications preinstallees (bloatware) — separe du debloat WinUtil.
  Dry-run par defaut ; suppression avec -Apply + confirmation (agent) ou -Apply explicite (launcher).
#>

function Get-FreshWindowsAppxBloatwareConfigFileName {
    return 'appx-bloatware.json'
}

function Resolve-FreshWindowsAppxBloatwareConfigPath {
    param(
        [string]$ConfigPath = '',
        [string]$FreshAppData = '',
        [string]$RepoRoot = '',
        [string]$ConfigsBaseUrl = ''
    )
    if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
        return (Resolve-Path -LiteralPath $ConfigPath).Path
    }
    $fileName = Get-FreshWindowsAppxBloatwareConfigFileName
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($RepoRoot) {
        [void]$candidates.Add((Join-Path $RepoRoot ("configs\" + $fileName)))
    }
    if ($FreshAppData) {
        [void]$candidates.Add((Join-Path $FreshAppData ("configs\" + $fileName)))
    }
    if ($PSScriptRoot) {
        $repoGuess = Join-Path $PSScriptRoot '..\..\configs\' + $fileName
        try {
            $resolved = Resolve-Path -LiteralPath $repoGuess -ErrorAction Stop
            if ($resolved) { [void]$candidates.Add($resolved.Path) }
        }
        catch { }
    }
    foreach ($p in ($candidates | Select-Object -Unique)) {
        if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path }
    }
    if ($ConfigsBaseUrl) {
        try {
            $url = ($ConfigsBaseUrl.TrimEnd('/') + '/' + $fileName)
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ("fw-bloatware-{0}.json" -f [guid]::NewGuid().ToString('N'))
            Invoke-RestMethod -Uri $url -OutFile $tmp -UseBasicParsing
            return $tmp
        }
        catch { }
    }
    return $null
}

function Get-FreshWindowsAppxBloatwareConfig {
    param(
        [string]$ConfigPath = '',
        [string]$FreshAppData = $(if (Get-Command Get-FreshAgentAppDataRoot -ErrorAction SilentlyContinue) { Get-FreshAgentAppDataRoot } else { Join-Path $env:LOCALAPPDATA 'FreshWindows' }),
        [string]$RepoRoot = '',
        [string]$ConfigsBaseUrl = ''
    )
    $path = Resolve-FreshWindowsAppxBloatwareConfigPath -ConfigPath $ConfigPath -FreshAppData $FreshAppData `
        -RepoRoot $RepoRoot -ConfigsBaseUrl $ConfigsBaseUrl
    if (-not $path) {
        throw 'Config appx-bloatware.json introuvable.'
    }
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    return ($raw | ConvertFrom-Json)
}

function Test-FreshWindowsAppxPackageRuleMatch {
    param(
        [Parameter(Mandatory)][string]$PackageIdentity,
        [Parameter(Mandatory)][string]$Rule
    )
    $id = $PackageIdentity.Trim()
    $rule = $Rule.Trim()
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($rule)) { return $false }

    $name = $id
    if ($id -match '^([^_]+)') { $name = $Matches[1] }

    if ($rule.StartsWith('*') -and $rule.Length -gt 1) {
        $suffix = $rule.Substring(1)
        return ($id.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase))
    }
    if ($rule.EndsWith('.') -or $rule.EndsWith('*')) {
        $prefix = $rule.TrimEnd('.', '*')
        return ($name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            $id.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))
    }
    if ($name -ieq $rule) { return $true }
    if ($id -ieq $rule) { return $true }
    if ($id.StartsWith($rule + '_', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Test-FreshWindowsAppxRuleListMatch {
    param(
        [Parameter(Mandatory)][string]$PackageIdentity,
        $ExactList,
        $PrefixList,
        $SuffixList
    )
    foreach ($r in @($ExactList)) {
        if (Test-FreshWindowsAppxPackageRuleMatch -PackageIdentity $PackageIdentity -Rule ([string]$r)) {
            return $true
        }
    }
    foreach ($r in @($PrefixList)) {
        if (Test-FreshWindowsAppxPackageRuleMatch -PackageIdentity $PackageIdentity -Rule ([string]$r)) {
            return $true
        }
    }
    foreach ($r in @($SuffixList)) {
        if (Test-FreshWindowsAppxPackageRuleMatch -PackageIdentity $PackageIdentity -Rule ('*' + [string]$r)) {
            return $true
        }
    }
    return $false
}

function Get-FreshWindowsAppxBloatwareRemoveRuleLists {
    param($Config)
    $exact = @()
    $prefixes = @()
    if ($Config.remove) {
        if ($Config.remove.exact) { $exact += @($Config.remove.exact) }
        if ($Config.remove.prefixes) { $prefixes += @($Config.remove.prefixes) }
        if ($Config.remove.oem) {
            if ($Config.remove.oem.exact) { $exact += @($Config.remove.oem.exact) }
            if ($Config.remove.oem.prefixes) { $prefixes += @($Config.remove.oem.prefixes) }
        }
    }
    return @{ exact = $exact; prefixes = $prefixes }
}

function Get-FreshWindowsAppxBloatwareClassification {
    param(
        [Parameter(Mandatory)][string]$PackageIdentity,
        $Config,
        [bool]$IsFramework = $false,
        [bool]$IsNonRemovable = $false
    )
    if ($IsFramework -or $IsNonRemovable) {
        return 'Protected'
    }
    if (-not $Config) {
        return 'Unknown'
    }
    if (Test-FreshWindowsAppxRuleListMatch -PackageIdentity $PackageIdentity `
            -ExactList $Config.protected.exact -PrefixList $Config.protected.prefixes -SuffixList $Config.protected.suffixes) {
        return 'Protected'
    }
    if ($Config.confirmLater -and (Test-FreshWindowsAppxRuleListMatch -PackageIdentity $PackageIdentity `
            -ExactList $Config.confirmLater.exact -PrefixList @() -SuffixList @())) {
        return 'ConfirmLater'
    }
    $removeLists = Get-FreshWindowsAppxBloatwareRemoveRuleLists -Config $Config
    if (Test-FreshWindowsAppxRuleListMatch -PackageIdentity $PackageIdentity `
            -ExactList $removeLists.exact -PrefixList $removeLists.prefixes -SuffixList @()) {
        return 'Remove'
    }
    return 'Unknown'
}

function Get-FreshWindowsAppxBloatwareLogPath {
    param([string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'))
    $logDir = $FreshAppData
    if (Get-Command Get-FreshWindowsLogDir -ErrorAction SilentlyContinue) {
        try { $logDir = Get-FreshWindowsLogDir } catch { }
    }
    else {
        $logDir = Join-Path $FreshAppData 'logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    return (Join-Path $logDir ("appx-bloatware-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
}

function Write-FreshWindowsAppxBloatwareLogLine {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Result
    )
    $line = '{0}|{1}|{2}|{3}' -f (Get-Date -Format 'o'), $Package, $Action, $Result
    try {
        $dir = Split-Path $LogPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    }
    catch { }
}

function New-FreshWindowsAppxBloatwareRestorePoint {
    param([string]$Description = 'Fresh Windows appx bloatware')
    if (Get-Command New-FreshAgentRestorePoint -ErrorAction SilentlyContinue) {
        return New-FreshAgentRestorePoint -Description $Description
    }
    $elevated = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { $elevated = $false }
    if (-not $elevated) {
        return @{ ok = $false; message = 'Point de restauration ignore: session non administrateur.' }
    }
    try {
        $status = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber -Descending | Select-Object -First 1
        if ($status) {
            $last = $status.CreationTime
            if (((Get-Date) - $last).TotalMinutes -lt 24) {
                return @{ ok = $true; message = 'Point de restauration recent (<24h) — creation ignoree (limite Windows).' }
            }
        }
    }
    catch { }
    try {
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue | Out-Null
    }
    catch { }
    try {
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        return @{ ok = $true; message = "Point de restauration: $Description" }
    }
    catch {
        return @{ ok = $false; message = "Restore point: $($_.Exception.Message)" }
    }
}

function Get-FreshWindowsAppxBloatwareCdmBackupPath {
    param([string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows'))
    return (Join-Path $FreshAppData 'appx-bloatware-cdm-backup.json')
}

function Set-FreshWindowsContentDeliveryManagerSilentInstall {
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$Revert,
        [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows')
    )
    $cdm = $Config.contentDeliveryManager
    if (-not $cdm -or -not $cdm.registryPath -or -not $cdm.values) {
        return @{ ok = $false; message = 'CDM: config absente.' }
    }
    $regPath = [string]$cdm.registryPath
    $backupPath = Get-FreshWindowsAppxBloatwareCdmBackupPath -FreshAppData $FreshAppData
    $notes = [System.Collections.ArrayList]@()

    if ($Revert) {
        if (-not (Test-Path -LiteralPath $backupPath)) {
            return @{ ok = $false; message = 'CDM: aucune sauvegarde pour restauration.' }
        }
        try {
            $saved = Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @($saved.values)) {
                $name = [string]$entry.name
                if (-not (Test-Path -LiteralPath $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                if ($null -eq $entry.value) {
                    Remove-ItemProperty -LiteralPath $regPath -Name $name -ErrorAction SilentlyContinue
                }
                else {
                    Set-ItemProperty -LiteralPath $regPath -Name $name -Value ([int]$entry.value) -Type DWord -Force
                }
            }
            [void]$notes.Add('CDM restaure depuis backup.')
            return @{ ok = $true; message = ($notes -join ' ') }
        }
        catch {
            return @{ ok = $false; message = "CDM revert: $($_.Exception.Message)" }
        }
    }

    $backup = @{ at = (Get-Date).ToString('o'); values = @() }
    foreach ($v in @($cdm.values)) {
        $name = [string]$v.name
        $current = $null
        try {
            if (Test-Path -LiteralPath $regPath) {
                $current = Get-ItemProperty -LiteralPath $regPath -Name $name -ErrorAction SilentlyContinue
            }
        }
        catch { }
        $prevVal = $null
        if ($current) { $prevVal = $current.$name }
        $backup.values += @{ name = $name; value = $prevVal }
        try {
            if (-not (Test-Path -LiteralPath $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -LiteralPath $regPath -Name $name -Value ([int]$v.disabled) -Type DWord -Force
            [void]$notes.Add("CDM $name=0")
        }
        catch {
            [void]$notes.Add("CDM $name echec")
        }
    }
    try {
        ($backup | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $backupPath -Encoding UTF8
    }
    catch { }
    return @{ ok = $true; message = ($notes -join '; ') }
}

function Get-FreshWindowsAppxBloatwareInventory {
    param(
        $Config,
        [string[]]$PackageIdentities = @()
    )
    $items = [System.Collections.ArrayList]@()
    $seen = @{}

    $addItem = {
        param($Identity, $Scope, $IsFramework, $IsNonRemovable)
        $key = ('{0}|{1}' -f $Scope, $Identity)
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        $class = Get-FreshWindowsAppxBloatwareClassification -PackageIdentity $Identity -Config $Config `
            -IsFramework $IsFramework -IsNonRemovable $IsNonRemovable
        [void]$items.Add([pscustomobject]@{
                Identity       = $Identity
                Scope          = $Scope
                Classification = $class
            })
    }

    if ($PackageIdentities -and $PackageIdentities.Count -gt 0) {
        foreach ($id in $PackageIdentities) {
            & $addItem $id 'Test' $false $false
        }
        return @($items)
    }

    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        try {
            Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object {
                $id = if ($_.Name) { [string]$_.Name } else { [string]$_.PackageFullName }
                & $addItem $id 'User' $_.IsFramework $_.IsNonRemovable
            }
        }
        catch {
            Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object {
                $id = if ($_.Name) { [string]$_.Name } else { [string]$_.PackageFullName }
                & $addItem $id 'User' $_.IsFramework $_.IsNonRemovable
            }
        }
    }
    if (Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue) {
        try {
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | ForEach-Object {
                $id = if ($_.DisplayName) { [string]$_.DisplayName } else { [string]$_.PackageName }
                & $addItem $id 'Provisioned' $false $false
            }
        }
        catch { }
    }
    return @($items)
}

function Invoke-FreshWindowsAppxBloatwareCleanup {
    param(
        [switch]$Apply,
        [switch]$DisableSilentInstall,
        [switch]$RevertSilentInstall,
        [string]$ConfigPath = '',
        [string]$FreshAppData = $(if (Get-Command Get-FreshAgentAppDataRoot -ErrorAction SilentlyContinue) { Get-FreshAgentAppDataRoot } else { Join-Path $env:LOCALAPPDATA 'FreshWindows' }),
        [string]$RepoRoot = '',
        [string]$ConfigsBaseUrl = '',
        [string[]]$PackageIdentities = @()
    )

    $config = Get-FreshWindowsAppxBloatwareConfig -ConfigPath $ConfigPath -FreshAppData $FreshAppData `
        -RepoRoot $RepoRoot -ConfigsBaseUrl $ConfigsBaseUrl
    $inventory = Get-FreshWindowsAppxBloatwareInventory -Config $config -PackageIdentities $PackageIdentities
    $toRemove = @($inventory | Where-Object { $_.Classification -eq 'Remove' })
    $protected = @($inventory | Where-Object { $_.Classification -eq 'Protected' })
    $unknown = @($inventory | Where-Object { $_.Classification -eq 'Unknown' })
    $later = @($inventory | Where-Object { $_.Classification -eq 'ConfirmLater' })

    $logPath = Get-FreshWindowsAppxBloatwareLogPath -FreshAppData $FreshAppData
    $notes = [System.Collections.ArrayList]@()

    if ($RevertSilentInstall) {
        $cdm = Set-FreshWindowsContentDeliveryManagerSilentInstall -Config $config -Revert -FreshAppData $FreshAppData
        [void]$notes.Add([string]$cdm.message)
        return @{
            ok       = [bool]$cdm.ok
            message  = ($notes -join ' ')
            logPath  = $logPath
            dryRun   = $true
            removed  = @()
            skipped  = @()
        }
    }

    if (-not $Apply) {
        foreach ($item in $toRemove) {
            Write-FreshWindowsAppxBloatwareLogLine -LogPath $logPath -Package $item.Identity -Action 'dry-run' -Result 'would-remove'
        }
        foreach ($item in $unknown) {
            Write-FreshWindowsAppxBloatwareLogLine -LogPath $logPath -Package $item.Identity -Action 'add-candidate' -Result 'unknown-never-removed'
        }
        $addCandidates = @($unknown | ForEach-Object { $_.Identity } | Select-Object -Unique)
        $summary = "Simulation: {0} a retirer, {1} proteges, {2} candidats a ajouter (inconnus), {3} a confirmer." -f `
            $toRemove.Count, $protected.Count, $addCandidates.Count, $later.Count
        [void]$notes.Add($summary)
        [void]$notes.Add("Journal: $logPath")
        if ($toRemove.Count -gt 0) {
            $sample = ($toRemove | Select-Object -First 20 | ForEach-Object { $_.Identity }) -join ', '
            [void]$notes.Add("A retirer (extraits): $sample")
        }
        if ($addCandidates.Count -gt 0) {
            $cand = ($addCandidates | Select-Object -First 30) -join ', '
            [void]$notes.Add("Candidats a ajouter a la config (jamais supprimes): $cand")
            if ($addCandidates.Count -gt 30) {
                [void]$notes.Add(("... et {0} autre(s) candidat(s)." -f ($addCandidates.Count - 30)))
            }
        }
        return @{
            ok            = $true
            message       = ($notes -join ' ')
            logPath       = $logPath
            dryRun        = $true
            toRemove      = @($toRemove | ForEach-Object { $_.Identity })
            protected     = @($protected | ForEach-Object { $_.Identity })
            unknown       = $addCandidates
            addCandidates = $addCandidates
            confirmLater  = @($later | ForEach-Object { $_.Identity })
        }
    }

    $rp = New-FreshWindowsAppxBloatwareRestorePoint
    [void]$notes.Add([string]$rp.message)

    if ($DisableSilentInstall) {
        $cdm = Set-FreshWindowsContentDeliveryManagerSilentInstall -Config $config -FreshAppData $FreshAppData
        [void]$notes.Add([string]$cdm.message)
        Write-FreshWindowsAppxBloatwareLogLine -LogPath $logPath -Package 'ContentDeliveryManager' -Action 'cdm-tweak' -Result ([string]$cdm.message)
    }

    $removed = [System.Collections.ArrayList]@()
    $skipped = [System.Collections.ArrayList]@()

    foreach ($item in $toRemove) {
        $identity = [string]$item.Identity
        $okRemove = $true
        if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
            $pkgs = @()
            try {
                $pkgs = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $identity })
            }
            catch {
                $pkgs = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $identity })
            }
            foreach ($pkg in $pkgs) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                    Write-FreshWindowsAppxBloatwareLogLine -LogPath $logPath -Package $identity -Action 'remove-user' -Result 'ok'
                }
                catch {
                    $okRemove = $false
                    Write-FreshWindowsAppxBloatwareLogLine -LogPath $logPath -Package $identity -Action 'remove-user' -Result $_.Exception.Message
                }
            }
        }
        if (Get-Command Get-AppxProvisionedPackage -ErrorAction SilentlyContinue) {
            try {
                $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -ieq $identity -or $_.PackageName -like ($identity + '*') })
                foreach ($p in $prov) {
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop
                        Write-FreshWindowsAppxBloatwareLogLine -LogPath $logPath -Package $identity -Action 'remove-provisioned' -Result 'ok'
                    }
                    catch {
                        $okRemove = $false
                        Write-FreshWindowsAppxBloatwareLogLine -LogPath $logPath -Package $identity -Action 'remove-provisioned' -Result $_.Exception.Message
                    }
                }
            }
            catch {
                Write-FreshWindowsAppxBloatwareLogLine -LogPath $logPath -Package $identity -Action 'remove-provisioned' -Result $_.Exception.Message
            }
        }
        if ($okRemove) { [void]$removed.Add($identity) } else { [void]$skipped.Add($identity) }
    }

    if ($unknown.Count -gt 0) {
        [void]$notes.Add(("{0} paquet(s) inconnu(s) ignores (jamais supprimes)." -f $unknown.Count))
    }
    [void]$notes.Add(("Suppression: {0} OK, {1} partiels/echecs." -f $removed.Count, $skipped.Count))
    [void]$notes.Add("Journal: $logPath")

    return @{
        ok            = ($skipped.Count -eq 0)
        message       = ($notes -join ' ')
        logPath       = $logPath
        dryRun        = $false
        removed       = @($removed)
        skipped       = @($skipped)
        addCandidates = @($unknown | ForEach-Object { $_.Identity } | Select-Object -Unique)
    }
}

function Wait-FreshWindowsBloatwareApplyConfirm {
    param(
        [string]$Prompt = 'Tape oui pour supprimer les apps preinstallees listees, autre pour annuler'
    )
    Write-Host $Prompt -ForegroundColor Yellow
    $line = Read-Host
    if (Get-Command Resolve-FreshAgentConfirmUtterance -ErrorAction SilentlyContinue) {
        $d = Resolve-FreshAgentConfirmUtterance -Transcript ([string]$line)
        if ($d -eq 'confirm') { return $true }
        if ($d -eq 'cancel') { return $false }
    }
    $n = ([string]$line).Trim().ToLowerInvariant()
    if ($n -match '^(oui|ouais|ok|yes|confirme|valide|go)$') { return $true }
    return $false
}

function Invoke-FreshWindowsAppxBloatwareMenu {
    param(
        [string]$ConfigsBaseUrl = '',
        [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows')
    )
    do {
        Clear-Host
        Write-Host '=== NETTOYAGE APPS PREINSTALLEES ===' -ForegroundColor Cyan
        Write-Host 'Liste versionnee configs/appx-bloatware.json (separe du debloat WinUtil).' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '1. Simulation (liste sans supprimer) *' -ForegroundColor Green
        Write-Host '2. Suppression reelle (point de restauration + confirmation)' -ForegroundColor Yellow
        Write-Host '3. Restaurer suggestions Windows (CDM)' -ForegroundColor Gray
        Write-Host '4. Retour' -ForegroundColor DarkGray
        Write-Host ''
        $c = Read-Host 'Choix'
        switch ($c) {
            '1' {
                $r = Invoke-FreshWindowsAppxBloatwareCleanup -ConfigsBaseUrl $ConfigsBaseUrl -FreshAppData $FreshAppData
                Write-Host $r.message -ForegroundColor Cyan
                if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
            }
            '2' {
                $preview = Invoke-FreshWindowsAppxBloatwareCleanup -ConfigsBaseUrl $ConfigsBaseUrl -FreshAppData $FreshAppData
                Write-Host $preview.message -ForegroundColor Cyan
                if ($preview.toRemove.Count -eq 0) {
                    Write-Host 'Rien a supprimer selon la config.' -ForegroundColor Yellow
                    if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
                    continue
                }
                if (-not (Wait-FreshWindowsBloatwareApplyConfirm)) { continue }
                $r = Invoke-FreshWindowsAppxBloatwareCleanup -Apply -DisableSilentInstall `
                    -ConfigsBaseUrl $ConfigsBaseUrl -FreshAppData $FreshAppData
                Write-Host $r.message -ForegroundColor $(if ($r.ok) { 'Green' } else { 'Yellow' })
                if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
            }
            '3' {
                $r = Invoke-FreshWindowsAppxBloatwareCleanup -RevertSilentInstall -ConfigsBaseUrl $ConfigsBaseUrl -FreshAppData $FreshAppData
                Write-Host $r.message -ForegroundColor Cyan
                if (Get-Command Wait-ForUser -ErrorAction SilentlyContinue) { Wait-ForUser }
            }
            '4' { return }
            default {
                Write-Host 'Choix invalide' -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Invoke-SkillRemovePreinstalledApps {
    param(
        $Apply = $false,
        $DisableSilentInstall = $true,
        [string]$RepoRef = 'main',
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $asBool = {
        param($Value, [bool]$Default)
        if (Get-Command ConvertTo-FreshAgentBool -ErrorAction SilentlyContinue) {
            if ($null -eq $Value) { return $Default }
            return (ConvertTo-FreshAgentBool -Value $Value -Default $Default)
        }
        if ($null -eq $Value) { return $Default }
        if ($Value -is [bool]) { return [bool]$Value }
        $s = ([string]$Value).Trim().ToLowerInvariant()
        if ($s -match '^(1|true|yes|oui|on)$') { return $true }
        if ($s -match '^(0|false|no|non|off)$') { return $false }
        return $Default
    }
    $doApply = [bool](& $asBool $Apply $false)
    $doCdm = [bool](& $asBool $DisableSilentInstall $true)
    $repoRoot = ''
    if ($PSScriptRoot) {
        $tryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        if (Test-Path -LiteralPath (Join-Path $tryRoot 'configs\appx-bloatware.json')) {
            $repoRoot = $tryRoot
        }
    }
    $baseUrl = "https://raw.githubusercontent.com/nico2511/fresh_windows/$RepoRef/configs"
    $params = @{
        FreshAppData   = $FreshAppData
        RepoRoot       = $repoRoot
        ConfigsBaseUrl = $baseUrl
        DisableSilentInstall = $doCdm
    }
    if (-not $doApply) {
        return Invoke-FreshWindowsAppxBloatwareCleanup @params
    }
    return Invoke-FreshWindowsAppxBloatwareCleanup -Apply @params
}

function Offer-FreshWindowsAppxBloatwarePreviewStep {
    param(
        [string]$ConfigsBaseUrl = '',
        [string]$FreshAppData = $(Join-Path $env:LOCALAPPDATA 'FreshWindows')
    )
    $answer = Read-Host 'Apercu nettoyage apps preinstallees (simulation, sans rien supprimer) ? (o/N)'
    if ($answer -notmatch '^(o|oui|y|yes)$') { return }
    $r = Invoke-FreshWindowsAppxBloatwareCleanup -ConfigsBaseUrl $ConfigsBaseUrl -FreshAppData $FreshAppData
    Write-Host $r.message -ForegroundColor Cyan
}
