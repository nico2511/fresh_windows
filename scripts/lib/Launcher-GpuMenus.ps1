#Requires -Version 5.1

function Open-GpuMenu {
    $gpu = Get-ConfigObject -FileName "gpu.json"
    do {
        Clear-Host
        Write-Host "=== CARTE GRAPHIQUE ===" -ForegroundColor Cyan
        Write-Host "1. AMD (Adrenalin / Ryzen Master)" -ForegroundColor Red
        Write-Host "2. NVIDIA" -ForegroundColor Green
        Write-Host "3. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" { Open-AmdGpuMenu -GpuConfig $gpu }
            "2" { Open-NvidiaGpuMenu -GpuConfig $gpu }
            "3" { return }
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
    if (-not $downloads -or -not (Test-Path -LiteralPath $downloads)) {
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
