#Requires -Version 5.1

function Open-GpuMenu {
    $gpu = Get-ConfigObject -FileName "gpu.json"
    do {
        Clear-Host
        Write-Host "=== CARTE GRAPHIQUE ===" -ForegroundColor Cyan
        Write-Host "1. AMD" -ForegroundColor Red
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

function Open-AmdGpuMenu {
    param($GpuConfig)
    do {
        Clear-Host
        Write-Host "=== AMD / ADRENALIN ===" -ForegroundColor Red
        Write-Host "1. Télécharger Adrenalin (setup minimal)" -ForegroundColor Yellow
        Write-Host "2. Ouvrir la page drivers AMD" -ForegroundColor White
        Write-Host "3. Ouvrir le guide de config Adrenalin" -ForegroundColor Cyan
        Write-Host "4. Retour" -ForegroundColor Gray
        Write-Host ""
        $c = Read-Host "Choix"

        switch ($c) {
            "1" {
                $url = if ($GpuConfig -and $GpuConfig.amd.downloadUrl) { $GpuConfig.amd.downloadUrl } else {
                    "https://drivers.amd.com/drivers/installer/26.10/whql/amd-software-adrenalin-edition-26.8.1-minimalsetup-260818_web.exe"
                }
                $dest = Join-Path $env:TEMP "amd-adrenalin-minimalsetup.exe"
                Write-Host "`n→ Téléchargement Adrenalin..." -ForegroundColor Yellow
                Write-Host "  $url" -ForegroundColor DarkGray
                try {
                    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
                    Write-Host "  Sauvé : $dest" -ForegroundColor Green
                    Start-Process $dest
                }
                catch {
                    Write-Host "Échec téléchargement : $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "Ouverture de la page drivers à la place..." -ForegroundColor Yellow
                    $page = if ($GpuConfig) { $GpuConfig.amd.driversPage } else { "https://www.amd.com/en/support/download/drivers.html" }
                    Start-Process $page
                }
                Wait-ForUser
            }
            "2" {
                $page = if ($GpuConfig) { $GpuConfig.amd.driversPage } else { "https://www.amd.com/en/support/download/drivers.html" }
                Start-Process $page
            }
            "3" {
                $guide = if ($GpuConfig -and $GpuConfig.amd.guideUrl) { $GpuConfig.amd.guideUrl } else { "$GuidesBaseUrl/amd-adrenalin.md" }
                Start-Process $guide
            }
            "4" { return }
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
