#Requires -Version 5.1

function Open-GpuMenu {
    $gpu = Get-ConfigObject -FileName "gpu.json"
    do {
        Clear-Host
        Write-Host "=== GPU / CHIPSET ===" -ForegroundColor Cyan
        Write-Host "1. AMD (Adrenalin / Ryzen Master)" -ForegroundColor Red
        Write-Host "2. NVIDIA" -ForegroundColor Green
        Write-Host "3. Chipset (auto Intel / AMD)" -ForegroundColor Yellow
        Write-Host "4. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" { Open-AmdGpuMenu -GpuConfig $gpu }
            "2" { Open-NvidiaGpuMenu -GpuConfig $gpu }
            "3" { Open-ChipsetMenu -GpuConfig $gpu }
            "4" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Get-AmdCpuName {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu -and $cpu.Name) { return [string]$cpu.Name }
    } catch { }
    return ''
}

function Test-IsLaptopChassis {
    try {
        $chassis = Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop
        $laptopTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
        foreach ($t in @($chassis.ChassisTypes)) {
            if ($laptopTypes -contains [int]$t) { return $true }
        }
    } catch { }
    return $false
}

function Get-SystemChipsetInfo {
    $cpuName = ''
    $cpuManufacturer = ''
    $boardManufacturer = ''
    $boardProduct = ''

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu) {
            if ($cpu.Name) { $cpuName = [string]$cpu.Name }
            if ($cpu.Manufacturer) { $cpuManufacturer = [string]$cpu.Manufacturer }
        }
    } catch { }

    try {
        $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        if ($board) {
            if ($board.Manufacturer) { $boardManufacturer = [string]$board.Manufacturer }
            if ($board.Product) { $boardProduct = [string]$board.Product }
        }
    } catch { }

    $vendor = 'Other'
    $blob = "$cpuManufacturer $cpuName"
    if ($blob -match '(?i)AMD|Ryzen|Threadripper|Athlon') {
        $vendor = 'AMD'
    }
    elseif ($blob -match '(?i)Intel') {
        $vendor = 'Intel'
    }

    return [pscustomobject]@{
        Vendor            = $vendor
        CpuName           = $cpuName
        CpuManufacturer   = $cpuManufacturer
        BoardManufacturer = $boardManufacturer
        BoardProduct      = $boardProduct
        IsLaptop          = (Test-IsLaptopChassis)
    }
}

function Resolve-AmdChipsetDownload {
    param($GpuConfig)

    $cfg = $null
    if ($GpuConfig -and $GpuConfig.chipset -and $GpuConfig.chipset.amd) {
        $cfg = $GpuConfig.chipset.amd
    }

    $page = if ($cfg -and $cfg.supportPage) {
        [string]$cfg.supportPage
    } else {
        'https://www.amd.com/en/support/download/drivers.html'
    }
    $defaultUrl = if ($cfg -and $cfg.defaultDownloadUrl) {
        [string]$cfg.defaultDownloadUrl
    } else {
        $null
    }

    $cpuName = Get-AmdCpuName
    $label = 'CPU non mappe'
    $url = $null

    if ($cpuName -and $cfg -and $cfg.bySocket) {
        foreach ($rule in @($cfg.bySocket)) {
            if (-not $rule.match) { continue }
            if ($cpuName -match $rule.match) {
                $label = if ($rule.label) { [string]$rule.label } else { [string]$rule.match }
                if ($rule.downloadUrl) { $url = [string]$rule.downloadUrl }
                if ($rule.page) { $page = [string]$rule.page }
                break
            }
        }
    }

    if (-not $url -and $defaultUrl -and $label -ne 'CPU non mappe') {
        $url = $defaultUrl
    }

    return [pscustomobject]@{
        CpuName = $cpuName
        Label   = $label
        Url     = $url
        Page    = $page
    }
}

function Find-IntelDsaExecutable {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Intel\Driver and Support Assistant\DSATray.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Intel\Driver and Support Assistant\IntelDriverAndSupportAssistant.exe'),
        (Join-Path $env:ProgramFiles 'Intel\Driver and Support Assistant\DSATray.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Intel\Driver and Support Assistant\DSATray.exe')
    )
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }

    $roots = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Intel'),
        (Join-Path $env:ProgramFiles 'Intel')
    )
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $found = Get-ChildItem -LiteralPath $root -Recurse -Filter 'DSATray.exe' -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}

function Install-IntelDriverSupportAssistant {
    param($GpuConfig)

    $wingetId = 'Intel.IntelDriverAndSupportAssistant'
    if ($GpuConfig -and $GpuConfig.chipset -and $GpuConfig.chipset.intel -and $GpuConfig.chipset.intel.wingetId) {
        $wingetId = [string]$GpuConfig.chipset.intel.wingetId
    }
    $supportPage = 'https://www.intel.com/content/www/us/en/support/detect.html'
    if ($GpuConfig -and $GpuConfig.chipset -and $GpuConfig.chipset.intel -and $GpuConfig.chipset.intel.supportPage) {
        $supportPage = [string]$GpuConfig.chipset.intel.supportPage
    }

    Write-Host "`n-> Intel Driver & Support Assistant (winget)..." -ForegroundColor Yellow
    Write-Host "  ID : $wingetId" -ForegroundColor DarkGray
    winget install -e --id $wingetId --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
    $ok = ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189)
    if (-not $ok) {
        Write-Host "  Echec winget (code $LASTEXITCODE) - ouverture page Intel..." -ForegroundColor Red
        Start-Process $supportPage
        return $false
    }

    Start-Sleep -Seconds 2
    $exe = Find-IntelDsaExecutable
    if ($exe) {
        Write-Host "  Lancement : $exe" -ForegroundColor Green
        Start-Process -FilePath $exe
        Write-Host "  Dans DSA : Scan for drivers (chipset + autres Intel)." -ForegroundColor DarkGray
    }
    else {
        Write-Host "  DSA installe mais exe introuvable - ouverture page detect." -ForegroundColor DarkYellow
        Start-Process $supportPage
    }
    return $true
}

function Install-AmdChipsetSoftware {
    param($GpuConfig)

    $resolved = Resolve-AmdChipsetDownload -GpuConfig $GpuConfig
    Write-Host "`n-> AMD Chipset Software" -ForegroundColor Yellow
    if ($resolved.CpuName) {
        Write-Host ("  CPU    : {0}" -f $resolved.CpuName) -ForegroundColor DarkGray
        Write-Host ("  Socket : {0}" -f $resolved.Label) -ForegroundColor DarkGray
    }

    if (-not $resolved.Url) {
        Write-Host "  Pas d'URL mappee pour ce CPU - ouverture page support AMD." -ForegroundColor Yellow
        Start-Process $resolved.Page
        return $false
    }

    Write-Host "  Telechargement..." -ForegroundColor Yellow
    Write-Host "  $($resolved.Url)" -ForegroundColor DarkGray
    try {
        $dest = Save-AmdWebInstaller -Url $resolved.Url -FileName 'amd-chipset-software.exe'
        Write-Host "  Sauve : $dest" -ForegroundColor Green
        Start-Process $dest
        Write-Host "  Suivre l'installeur puis redemarrer si demande." -ForegroundColor DarkGray
        return $true
    }
    catch {
        Write-Host "  Echec telechargement : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Ouverture page support AMD..." -ForegroundColor Yellow
        Start-Process $resolved.Page
        return $false
    }
}

function Open-ChipsetMenu {
    param($GpuConfig)

    do {
        $info = Get-SystemChipsetInfo
        Clear-Host
        Write-Host "=== CHIPSET ===" -ForegroundColor Yellow
        Write-Host ("Vendor  : {0}" -f $info.Vendor) -ForegroundColor DarkGray
        if ($info.CpuName) {
            Write-Host ("CPU     : {0}" -f $info.CpuName) -ForegroundColor DarkGray
        }
        if ($info.BoardManufacturer -or $info.BoardProduct) {
            Write-Host ("Carte   : {0} {1}" -f $info.BoardManufacturer, $info.BoardProduct) -ForegroundColor DarkGray
        }
        if ($info.IsLaptop) {
            Write-Host "Chassis : portable (pack constructeur souvent preferables)" -ForegroundColor DarkYellow
        }
        Write-Host ""
        Write-Host "1. Installer / ouvrir selon detection" -ForegroundColor Green
        Write-Host "2. Ouvrir le guide chipset" -ForegroundColor Cyan
        Write-Host "3. Ouvrir la page support (Intel ou AMD)" -ForegroundColor White
        Write-Host "4. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" {
                if ($info.IsLaptop) {
                    Write-Host "`nPortable detecte : preferer le support constructeur (ASUS, Lenovo, Dell...)." -ForegroundColor DarkYellow
                    Write-Host "Continuation avec l'outil editeur (Intel DSA / AMD Chipset) si tu confirmes." -ForegroundColor DarkGray
                }
                switch ($info.Vendor) {
                    'Intel' {
                        Install-IntelDriverSupportAssistant -GpuConfig $GpuConfig | Out-Null
                    }
                    'AMD' {
                        if ($info.IsLaptop) {
                            $page = 'https://www.amd.com/en/support/download/drivers.html'
                            if ($GpuConfig -and $GpuConfig.chipset -and $GpuConfig.chipset.amd -and $GpuConfig.chipset.amd.supportPage) {
                                $page = [string]$GpuConfig.chipset.amd.supportPage
                            }
                            Write-Host "`nLaptop AMD : ouverture page support (pas d'URL chipset desktop forcee)." -ForegroundColor Yellow
                            Start-Process $page
                        }
                        else {
                            Install-AmdChipsetSoftware -GpuConfig $GpuConfig | Out-Null
                        }
                    }
                    default {
                        Write-Host "`nVendor non Intel/AMD - rien a installer automatiquement." -ForegroundColor Yellow
                        Write-Host ("CPU : {0}" -f $info.CpuName) -ForegroundColor DarkGray
                    }
                }
                Wait-ForUser
            }
            "2" {
                $guide = if ($GpuConfig -and $GpuConfig.chipset -and $GpuConfig.chipset.guideUrl) {
                    [string]$GpuConfig.chipset.guideUrl
                } else {
                    "$GuidesBaseUrl/chipset.md"
                }
                Start-Process $guide
            }
            "3" {
                if ($info.Vendor -eq 'Intel') {
                    $page = 'https://www.intel.com/content/www/us/en/support/detect.html'
                    if ($GpuConfig -and $GpuConfig.chipset -and $GpuConfig.chipset.intel -and $GpuConfig.chipset.intel.supportPage) {
                        $page = [string]$GpuConfig.chipset.intel.supportPage
                    }
                }
                else {
                    $page = 'https://www.amd.com/en/support/download/drivers.html'
                    if ($GpuConfig -and $GpuConfig.chipset -and $GpuConfig.chipset.amd -and $GpuConfig.chipset.amd.supportPage) {
                        $page = [string]$GpuConfig.chipset.amd.supportPage
                    }
                }
                Start-Process $page
            }
            "4" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Resolve-RyzenMasterDownload {
    param($GpuConfig)

    $page = if ($GpuConfig -and $GpuConfig.amd.ryzenMasterPage) {
        $GpuConfig.amd.ryzenMasterPage
    } else {
        'https://www.amd.com/en/products/software/ryzen-master.html'
    }
    $defaultUrl = if ($GpuConfig -and $GpuConfig.amd.ryzenMaster.defaultUrl) {
        $GpuConfig.amd.ryzenMaster.defaultUrl
    } else {
        $null
    }

    $cpuName = Get-AmdCpuName
    $label = 'CPU inconnu'
    $url = $defaultUrl

    if ($cpuName -and $GpuConfig -and $GpuConfig.amd.ryzenMaster.byCpuPattern) {
        foreach ($rule in @($GpuConfig.amd.ryzenMaster.byCpuPattern)) {
            if (-not $rule.match) { continue }
            if ($cpuName -match $rule.match) {
                $label = if ($rule.label) { [string]$rule.label } else { $rule.match }
                if ($rule.url) { $url = [string]$rule.url }
                break
            }
        }
    }

    return [pscustomobject]@{
        CpuName = $cpuName
        Label   = $label
        Url     = $url
        Page    = $page
    }
}

function Save-AmdWebInstaller {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$FileName
    )

    $downloads = [Environment]::GetFolderPath('UserProfile')
    if ($downloads) {
        $downloads = Join-Path $downloads 'Downloads'
    }
    if (-not $downloads -or (-not (Test-Path -LiteralPath $downloads))) {
        $downloads = $env:TEMP
    }
    New-Item -ItemType Directory -Path $downloads -Force | Out-Null
    $dest = Join-Path $downloads $FileName

    $headers = @{
        'Referer'    = 'https://www.amd.com/'
        'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }

    Write-Host "  Dest : $dest" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing -Headers $headers -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $dest)) {
        throw 'Fichier absent apres telechargement.'
    }
    $item = Get-Item -LiteralPath $dest
    if ($item.Length -lt 500KB) {
        throw ("Fichier trop petit ({0} octets) - probablement une page HTML AMD, pas l'installeur." -f $item.Length)
    }
    $fs = [System.IO.File]::OpenRead($dest)
    try {
        $b0 = $fs.ReadByte()
        $b1 = $fs.ReadByte()
    }
    finally { $fs.Close() }
    # MZ
    if ($b0 -ne 0x4D -or $b1 -ne 0x5A) {
        throw 'Le fichier telecharge n''est pas un executable PE (MZ).'
    }
    return $dest
}

function Open-AmdGpuMenu {
    param($GpuConfig)
    do {
        Clear-Host
        Write-Host "=== AMD / ADRENALIN ===" -ForegroundColor Red
        Write-Host "1. Telecharger Adrenalin (setup minimal)" -ForegroundColor Yellow
        Write-Host "2. Telecharger / ouvrir Ryzen Master (selon CPU)" -ForegroundColor Magenta
        Write-Host "3. Ouvrir la page drivers AMD" -ForegroundColor White
        Write-Host "4. Ouvrir le guide de config Adrenalin" -ForegroundColor Cyan
        Write-Host "5. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" {
                $url = if ($GpuConfig -and $GpuConfig.amd.downloadUrl) { $GpuConfig.amd.downloadUrl } else {
                    "https://drivers.amd.com/drivers/installer/26.10/whql/amd-software-adrenalin-edition-26.8.1-minimalsetup-260818_web.exe"
                }
                Write-Host "`n-> Telechargement Adrenalin..." -ForegroundColor Yellow
                Write-Host "  $url" -ForegroundColor DarkGray
                try {
                    $dest = Save-AmdWebInstaller -Url $url -FileName 'amd-adrenalin-minimalsetup.exe'
                    Write-Host "  Sauve : $dest" -ForegroundColor Green
                    Start-Process $dest
                }
                catch {
                    Write-Host "Echec telechargement : $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "Ouverture de la page drivers a la place..." -ForegroundColor Yellow
                    $page = if ($GpuConfig) { $GpuConfig.amd.driversPage } else { "https://www.amd.com/en/support/download/drivers.html" }
                    Start-Process $page
                }
                Wait-ForUser
            }
            "2" {
                $rm = Resolve-RyzenMasterDownload -GpuConfig $GpuConfig
                Write-Host "`n-> Ryzen Master" -ForegroundColor Magenta
                if ($rm.CpuName) {
                    Write-Host ("  CPU : {0}" -f $rm.CpuName) -ForegroundColor DarkGray
                    Write-Host ("  Profil : {0}" -f $rm.Label) -ForegroundColor DarkGray
                }
                if ($rm.Url) {
                    Write-Host "  Telechargement..." -ForegroundColor Yellow
                    try {
                        $dest = Save-AmdWebInstaller -Url $rm.Url -FileName 'amd-ryzen-master.exe'
                        Write-Host "  Sauve : $dest" -ForegroundColor Green
                        Start-Process $dest
                    }
                    catch {
                        Write-Host "Echec : $($_.Exception.Message)" -ForegroundColor Red
                        Write-Host "Ouverture de la page Ryzen Master..." -ForegroundColor Yellow
                        Start-Process $rm.Page
                    }
                }
                else {
                    Write-Host "  URL non mappee pour ce CPU - ouverture page AMD." -ForegroundColor Yellow
                    Start-Process $rm.Page
                }
                Wait-ForUser
            }
            "3" {
                $page = if ($GpuConfig) { $GpuConfig.amd.driversPage } else { "https://www.amd.com/en/support/download/drivers.html" }
                Start-Process $page
            }
            "4" {
                $guide = if ($GpuConfig -and $GpuConfig.amd.guideUrl) { $GpuConfig.amd.guideUrl } else { "$GuidesBaseUrl/amd-adrenalin.md" }
                Start-Process $guide
            }
            "5" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}

function Open-NvidiaGpuMenu {
    param($GpuConfig)
    do {
        Clear-Host
        Write-Host "=== NVIDIA / NVCLEANSTALL ===" -ForegroundColor Green
        Write-Host "1. Ouvrir le guide NVCleanstall (GitHub)" -ForegroundColor Cyan
        Write-Host "2. Ouvrir la page drivers NVIDIA" -ForegroundColor White
        Write-Host "3. Ouvrir la page NVCleanstall" -ForegroundColor Yellow
        Write-Host "4. Installer NVCleanstall (winget)" -ForegroundColor Magenta
        Write-Host "5. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" {
                $guide = if ($GpuConfig -and $GpuConfig.nvidia.guideUrl) { $GpuConfig.nvidia.guideUrl } else { "$GuidesBaseUrl/nvidia-nvcleanstall.md" }
                Start-Process $guide
            }
            "2" {
                $page = if ($GpuConfig) { $GpuConfig.nvidia.driversPage } else { "https://www.nvidia.com/Download/index.aspx" }
                Start-Process $page
            }
            "3" {
                $page = if ($GpuConfig) { $GpuConfig.nvidia.nvcleanstallUrl } else { "https://www.techpowerup.com/download/techpowerup-nvcleanstall/" }
                Start-Process $page
            }
            "4" {
                winget install -e --id TechPowerUp.NVCleanstall --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
                Wait-ForUser
            }
            "5" { return }
            default {
                Write-Host "Choix invalide" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    } while ($true)
}
