#Requires -Version 5.1

function Get-FreshAgentInventoryPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'inventory.json'
}

function Get-SteamLibraryPaths {
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\libraryfolders.vdf'),
        (Join-Path $env:ProgramFiles 'Steam\steamapps\libraryfolders.vdf')
    )
    foreach ($vdf in $candidates) {
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        try {
            $lines = Get-Content -LiteralPath $vdf -Encoding UTF8
            foreach ($line in $lines) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $p = $Matches[1] -replace '\\\\', '\'
                    [void]$paths.Add($p)
                }
            }
            $steamRoot = Split-Path (Split-Path $vdf -Parent) -Parent
            [void]$paths.Add($steamRoot)
        }
        catch { }
    }
    return @($paths)
}

function Get-SteamInstalledGameNames {
    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($lib in (Get-SteamLibraryPaths)) {
        $apps = Join-Path $lib 'steamapps'
        if (-not (Test-Path -LiteralPath $apps)) { continue }
        foreach ($acf in (Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
            try {
                $c = Get-Content -LiteralPath $acf.FullName -Raw -Encoding UTF8
                if ($c -match '"name"\s+"([^"]+)"') {
                    [void]$names.Add($Matches[1].Trim())
                }
            }
            catch { }
        }
    }
    return @($names | Sort-Object)
}

function Get-DefaultBrowserName {
    try {
        $cmd = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' -Name ProgId -ErrorAction Stop).ProgId
        if ($cmd -match 'Chrome') { return 'Google Chrome' }
        if ($cmd -match 'Firefox') { return 'Mozilla Firefox' }
        if ($cmd -match 'Brave') { return 'Brave' }
        if ($cmd -match 'MSEdge') { return 'Microsoft Edge' }
        return $cmd
    }
    catch {
        return 'unknown'
    }
}

function Get-InstalledBrowserPaths {
    $list = @()
    $candidates = @(
        @{ Name = 'Brave'; Path = "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe" },
        @{ Name = 'Edge'; Path = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" },
        @{ Name = 'Firefox'; Path = "${env:ProgramFiles}\Mozilla Firefox\firefox.exe" },
        @{ Name = 'Chrome'; Path = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe" }
    )
    foreach ($b in $candidates) {
        if (Test-Path -LiteralPath $b.Path) {
            $list += @{ name = $b.Name; path = $b.Path }
        }
    }
    return $list
}

function Build-FreshAgentMachineInventory {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $games = Get-SteamInstalledGameNames
    $inv = [ordered]@{
        schemaVersion = 1
        generatedAt   = (Get-Date).ToString('o')
        hostname      = $env:COMPUTERNAME
        defaultBrowser = Get-DefaultBrowserName
        browsers      = @(Get-InstalledBrowserPaths)
        steamGames    = @($games)
        steamGameCount = $games.Count
    }
    $path = Get-FreshAgentInventoryPath -FreshAppData $FreshAppData
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    ($inv | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding UTF8
    return $inv
}

function Get-FreshAgentMachineInventory {
    param(
        [switch]$RefreshIfMissing,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $path = Get-FreshAgentInventoryPath -FreshAppData $FreshAppData
    if (-not (Test-Path -LiteralPath $path)) {
        if ($RefreshIfMissing) {
            return Build-FreshAgentMachineInventory -FreshAppData $FreshAppData
        }
        return $null
    }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { return $null }
}

function Get-FreshAgentInventoryContextText {
    param(
        [int]$MaxGames = 40,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $inv = Get-FreshAgentMachineInventory -RefreshIfMissing -FreshAppData $FreshAppData
    if (-not $inv) { return '' }
    $games = @($inv.steamGames)
    if ($games.Count -gt $MaxGames) {
        $games = $games[0..($MaxGames - 1)]
    }
    $browser = [string]$inv.defaultBrowser
    $gameList = if ($games.Count -gt 0) { ($games -join '; ') } else { '(aucun jeu Steam detecte)' }
    return "Inventaire machine ($($inv.generatedAt)): navigateur par defaut=$browser; jeux Steam ($($inv.steamGameCount)): $gameList"
}

function Invoke-SkillRefreshInventory {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $inv = Build-FreshAgentMachineInventory -FreshAppData $FreshAppData
    $msg = "Inventaire MAJ: $($inv.steamGameCount) jeux Steam, navigateur $($inv.defaultBrowser)."
    return @{ ok = $true; message = $msg }
}

function Invoke-SkillListMachineInventory {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $inv = Get-FreshAgentMachineInventory -RefreshIfMissing -FreshAppData $FreshAppData
    if (-not $inv) {
        return @{ ok = $false; message = 'Inventaire indisponible.' }
    }
    $sample = @($inv.steamGames | Select-Object -First 15) -join ', '
    $msg = "Navigateur: $($inv.defaultBrowser). Jeux Steam: $($inv.steamGameCount). Exemples: $sample"
    return @{ ok = $true; message = $msg }
}
