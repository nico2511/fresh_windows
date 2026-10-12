#Requires -Version 5.1
<#
  Actions Windows : volume, theme, settings, power, Start Menu apps.
#>

function ConvertTo-FreshAgentAppCompactKey {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.Trim().ToLowerInvariant()
    try {
        $formD = $t.Normalize([Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $formD.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($ch)
            }
        }
        $t = $sb.ToString()
    }
    catch { }
    return ([regex]::Replace($t, "[^a-z0-9]", ''))
}

function Get-FreshAgentEditDistance {
    param([string]$A, [string]$B)
    if ($null -eq $A) { $A = '' }
    if ($null -eq $B) { $B = '' }
    if ($A -eq $B) { return 0 }
    $n = $A.Length
    $m = $B.Length
    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }
    # bornes: trop long = pas un match voix
    if ([Math]::Abs($n - $m) -gt 6 -and [Math]::Max($n, $m) -gt 10) { return 99 }
    $prev = New-Object int[] ($m + 1)
    $curr = New-Object int[] ($m + 1)
    for ($j = 0; $j -le $m; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        $curr[0] = $i
        $ca = $A[$i - 1]
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($ca -eq $B[$j - 1]) { 0 } else { 1 }
            $curr[$j] = [Math]::Min([Math]::Min($curr[$j - 1] + 1, $prev[$j] + 1), $prev[$j - 1] + $cost)
        }
        $tmp = $prev; $prev = $curr; $curr = $tmp
    }
    return $prev[$m]
}

function Get-FreshAgentStartMenuCatalog {
    param([switch]$ForceRefresh)
    $now = Get-Date
    if (-not $ForceRefresh -and $script:FaStartMenuCatalog -and $script:FaStartMenuCatalogAt `
            -and (($now - [datetime]$script:FaStartMenuCatalogAt).TotalMinutes -lt 10)) {
        return @($script:FaStartMenuCatalog)
    }
    $roots = @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
    )
    $hits = [System.Collections.ArrayList]@()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $base = [IO.Path]::GetFileNameWithoutExtension($_.Name)
            [void]$hits.Add([pscustomobject]@{
                    Name    = $base
                    Path    = $_.FullName
                    Compact = (ConvertTo-FreshAgentAppCompactKey -Text $base)
                })
        }
    }
    $script:FaStartMenuCatalog = @($hits)
    $script:FaStartMenuCatalogAt = $now
    return @($script:FaStartMenuCatalog)
}

function Find-FreshAgentStartMenuApps {
    param([string]$Name)
    $catalog = @(Get-FreshAgentStartMenuCatalog)
    $key = ConvertTo-FreshAgentAppCompactKey -Text $Name
    if (-not $key) { return @($catalog | Select-Object Name, Path) }

    $scored = New-Object System.Collections.ArrayList
    foreach ($app in $catalog) {
        if (-not $app.Compact) { continue }
        $dist = 99
        $score = 0
        if ($app.Compact -eq $key) {
            $score = 1000
            $dist = 0
        }
        elseif ($key.Length -ge 5 -and $app.Compact.Length -ge 5 -and (
                $app.Compact.Contains($key) -or $key.Contains($app.Compact))) {
            # Sous-chaine seulement si assez long (evite "time" dans Runtime/etc.)
            $score = 700 - [Math]::Abs($app.Compact.Length - $key.Length)
            $dist = [Math]::Abs($app.Compact.Length - $key.Length)
        }
        else {
            $dist = Get-FreshAgentEditDistance -A $key -B $app.Compact
            $maxLen = [Math]::Max($key.Length, $app.Compact.Length)
            $allow = if ($maxLen -le 5) { 2 } elseif ($maxLen -le 9) { 3 } else { [Math]::Min(4, [int][Math]::Floor($maxLen * 0.4)) }
            if ($dist -le $allow) {
                $score = 500 - ($dist * 40)
            }
        }
        if ($score -gt 0) {
            [void]$scored.Add([pscustomobject]@{ Name = $app.Name; Path = $app.Path; Score = $score; Distance = $dist })
        }
    }
    if ($scored.Count -eq 0) { return @() }
    return @($scored | Sort-Object @{Expression = 'Score'; Descending = $true }, @{Expression = 'Distance'; Ascending = $true }, @{Expression = { $_.Name.Length }; Ascending = $true })
}

function Get-FreshAgentInstalledAppCatalog {
    <#
      Jeux / apps hors Start Menu: registre Uninstall + dossiers D:\Jeux, Steam common, EA...
    #>
    param([switch]$ForceRefresh)
    $now = Get-Date
    if (-not $ForceRefresh -and $script:FaInstalledAppCatalog -and $script:FaInstalledAppCatalogAt `
            -and (($now - [datetime]$script:FaInstalledAppCatalogAt).TotalMinutes -lt 15)) {
        return @($script:FaInstalledAppCatalog)
    }
    $hits = New-Object System.Collections.ArrayList
    $add = {
        param([string]$Display, [string]$Exe)
        if ([string]::IsNullOrWhiteSpace($Display) -or [string]::IsNullOrWhiteSpace($Exe)) { return }
        if (-not (Test-Path -LiteralPath $Exe)) { return }
        [void]$hits.Add([pscustomobject]@{
                Name    = $Display.Trim()
                Path    = $Exe
                Compact = (ConvertTo-FreshAgentAppCompactKey -Text $Display)
            })
    }
    $uninst = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($pat in $uninst) {
        Get-ItemProperty $pat -ErrorAction SilentlyContinue | ForEach-Object {
            $name = [string]$_.DisplayName
            if ([string]::IsNullOrWhiteSpace($name)) { return }
            $exe = $null
            if ($_.DisplayIcon) {
                $icon = ([string]$_.DisplayIcon).Trim().Trim('"')
                if ($icon -match ',\d+$') { $icon = ($icon -replace ',\d+$', '').Trim().Trim('"') }
                if ($icon -like '*.exe' -and (Test-Path -LiteralPath $icon)) { $exe = $icon }
            }
            if (-not $exe -and $_.InstallLocation -and (Test-Path -LiteralPath ([string]$_.InstallLocation))) {
                $dir = [string]$_.InstallLocation
                $guess = Get-ChildItem -LiteralPath $dir -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '(?i)unins|vcredist|redis|setup|crash|report|cef|update' } |
                    Sort-Object Length -Descending |
                    Select-Object -First 1
                if ($guess) { $exe = $guess.FullName }
            }
            if ($exe) { & $add $name $exe }
        }
    }
    foreach ($root in @(
            'D:\Jeux', 'E:\Jeux', 'D:\Games', 'E:\Games',
            (Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps\common'),
            (Join-Path $env:ProgramFiles 'Steam\steamapps\common'),
            (Join-Path $env:ProgramFiles 'EA Games'),
            (Join-Path ${env:ProgramFiles(x86)} 'EA Games'),
            (Join-Path $env:ProgramFiles 'Electronic Arts')
        )) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $dir = $_.FullName
            $exe = Get-ChildItem -LiteralPath $dir -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch '(?i)unins|vcredist|redis|setup|crash|report|cef|update|launcher' } |
                Sort-Object Length -Descending |
                Select-Object -First 1
            if ($exe) { & $add $_.Name $exe.FullName }
        }
    }
    $script:FaInstalledAppCatalog = @($hits)
    $script:FaInstalledAppCatalogAt = $now
    return @($script:FaInstalledAppCatalog)
}

function Find-FreshAgentInstalledApps {
    param([string]$Name)
    $key = ConvertTo-FreshAgentAppCompactKey -Text $Name
    if (-not $key) { return @() }
    $catalog = @(Get-FreshAgentInstalledAppCatalog)
    $scored = New-Object System.Collections.ArrayList
    foreach ($app in $catalog) {
        if (-not $app.Compact) { continue }
        $score = 0
        $dist = 99
        if ($app.Compact -eq $key) { $score = 1000; $dist = 0 }
        elseif ($key.Length -ge 5 -and (
                $app.Compact.Contains($key) -or $key.Contains($app.Compact))) {
            $score = 750 - [Math]::Abs($app.Compact.Length - $key.Length)
            $dist = [Math]::Abs($app.Compact.Length - $key.Length)
        }
        else {
            $dist = Get-FreshAgentEditDistance -A $key -B $app.Compact
            $maxLen = [Math]::Max($key.Length, $app.Compact.Length)
            $allow = if ($maxLen -le 5) { 2 } elseif ($maxLen -le 9) { 3 } else { [Math]::Min(4, [int][Math]::Floor($maxLen * 0.4)) }
            # "battlefield6" vs "battlefieldt6" (typo registre)
            if ($dist -le $allow) { $score = 520 - ($dist * 40) }
        }
        if ($score -gt 0) {
            [void]$scored.Add([pscustomobject]@{ Name = $app.Name; Path = $app.Path; Score = $score; Distance = $dist })
        }
    }
    if ($scored.Count -eq 0) { return @() }
    return @($scored | Sort-Object @{Expression = 'Score'; Descending = $true }, @{Expression = 'Distance'; Ascending = $true })
}

function Resolve-FreshAgentSpokenAppName {
    <#
      Resolut flou: Start Menu + apps/jeux installes (registre, D:\Jeux).
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$FreshAppData = ''
    )
    $hits = @(Find-FreshAgentStartMenuApps -Name $Name | Where-Object { $_ -and $_.Name })
    if ($hits.Count -gt 0 -and $hits[0].Score -ge 400) {
        return $hits[0].Name
    }
    $inst = @(Find-FreshAgentInstalledApps -Name $Name | Where-Object { $_ -and $_.Name })
    if ($inst.Count -gt 0 -and $inst[0].Score -ge 400) {
        return $inst[0].Name
    }
    # Catalogue skills-apps (cles + aliases)
    if (Get-Command Get-FreshAgentSkillsAppsConfig -ErrorAction SilentlyContinue) {
        try {
            $apps = Get-FreshAgentSkillsAppsConfig -RepoRef $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF } else { 'main' })
            $key = ConvertTo-FreshAgentAppCompactKey -Text $Name
            $best = $null
            $bestDist = 99
            foreach ($prop in @($apps.apps.PSObject.Properties)) {
                $cands = @($prop.Name) + @($prop.Value.aliases)
                foreach ($c in $cands) {
                    if (-not $c) { continue }
                    $ck = ConvertTo-FreshAgentAppCompactKey -Text ([string]$c)
                    if (-not $ck) { continue }
                    if ($ck -eq $key) { return [string]$prop.Name }
                    # Fuzzy: ignorer les alias trop courts (ide vs time = faux positif)
                    if ($key.Length -lt 4 -or $ck.Length -lt 4) { continue }
                    $d = Get-FreshAgentEditDistance -A $key -B $ck
                    $maxLen = [Math]::Max($key.Length, $ck.Length)
                    $allow = if ($maxLen -le 5) { 2 } elseif ($maxLen -le 9) { 3 } else { [Math]::Min(4, [int][Math]::Floor($maxLen * 0.4)) }
                    if ($d -le $allow -and $d -lt $bestDist) {
                        $bestDist = $d
                        $best = [string]$prop.Name
                    }
                }
            }
            if ($best) { return $best }
        }
        catch { }
    }
    return $Name
}

function Start-FreshAgentStartMenuApp {
    param([Parameter(Mandatory)][string]$Name)
    $resolvedName = Resolve-FreshAgentSpokenAppName -Name $Name
    # 1) Start Menu
    $hits = @(Find-FreshAgentStartMenuApps -Name $resolvedName | Where-Object { $_ -and $_.Path })
    if ($hits.Count -eq 0) {
        $hits = @(Find-FreshAgentStartMenuApps -Name $Name | Where-Object { $_ -and $_.Path })
    }
    # 2) Jeux / Uninstall (Battlefield 6, etc.)
    if ($hits.Count -eq 0 -or $hits[0].Score -lt 400) {
        $inst = @(Find-FreshAgentInstalledApps -Name $resolvedName)
        if ($inst.Count -eq 0) { $inst = @(Find-FreshAgentInstalledApps -Name $Name) }
        if ($inst.Count -gt 0 -and $inst[0].Score -ge 400) {
            Start-Process -FilePath $inst[0].Path
            $n = [string]$inst[0].Name
            return @{ ok = $true; message = ("Lance: {0}" -f $n); spoken = ("J'ouvre {0}." -f $n) }
        }
    }
    if (-not $hits -or $hits.Count -eq 0) {
        return @{
            ok      = $false
            message = "Application introuvable: $Name"
            spoken  = ("Je ne trouve pas {0}." -f $Name)
        }
    }
    $exact = $hits | Select-Object -First 1
    Start-Process -FilePath $exact.Path
    $msg = "Lance: $($exact.Name)"
    if ($resolvedName -ne $Name -and $exact.Name -ne $Name) {
        $msg = "Lance: $($exact.Name) (dit: $Name)"
    }
    return @{ ok = $true; message = $msg; spoken = ("J'ouvre {0}." -f $exact.Name) }
}

function Get-FreshAgentKnownAppFamilies {
    # Nom dit (habitude) -> clients alternatifs reels sur le PC
    return @{
        discord = @('Legcord', 'Vesktop', 'ArmCord', 'WebCord', 'Discord')
        chrome  = @('Google Chrome', 'Chromium', 'Brave', 'Chrome')
        edge    = @('Microsoft Edge', 'Edge')
    }
}

function Ensure-FreshAgentCommonAppAliases {
    <#
      Si Legcord est installe mais pas Discord, cree alias discord -> Legcord (une fois).
    #>
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    if (-not (Get-Command Set-FreshAgentAppAlias -ErrorAction SilentlyContinue)) { return @() }
    $created = @()
    $families = Get-FreshAgentKnownAppFamilies
    foreach ($spoken in @($families.Keys)) {
        $clients = @($families[$spoken])
        $found = $null
        foreach ($c in $clients) {
            $hits = @()
            if (Get-Command Find-FreshAgentStartMenuApps -ErrorAction SilentlyContinue) {
                $hits = @(Find-FreshAgentStartMenuApps -Name $c | Where-Object { $_.Score -ge 700 })
            }
            if ($hits.Count -eq 0 -and (Get-Command Find-FreshAgentInstalledApps -ErrorAction SilentlyContinue)) {
                $hits = @(Find-FreshAgentInstalledApps -Name $c | Where-Object { $_.Score -ge 700 })
            }
            if ($hits.Count -gt 0) {
                $found = $hits[0]
                break
            }
        }
        if (-not $found) { continue }
        # Ne pas ecraser un alias user deja present avec un exe
        $apps = $null
        if (Get-Command Get-FreshAgentSkillsAppsConfig -ErrorAction SilentlyContinue) {
            $apps = Get-FreshAgentSkillsAppsConfig -FreshAppData $FreshAppData
        }
        $hasPath = $false
        if ($apps -and $apps.apps) {
            foreach ($p in $apps.apps.PSObject.Properties) {
                $aliases = @($p.Value.aliases) + @($p.Name)
                if ($aliases | Where-Object { $_ -and $_.ToString().ToLowerInvariant() -eq $spoken }) {
                    if ($p.Value.paths -and @($p.Value.paths).Count -gt 0) {
                        $hasPath = $true
                        break
                    }
                }
            }
        }
        if ($hasPath) { continue }
        # Si le client trouve n'est pas le nom "canonique" (ex: Legcord pour discord), aliaser
        $canon = $clients | Where-Object { $_.ToLowerInvariant() -eq $spoken } | Select-Object -First 1
        if ($canon -and $found.Name -eq $canon) { continue }
        $r = Set-FreshAgentAppAlias -SpokenName $spoken -TargetName $found.Name -ExePath $found.Path -FreshAppData $FreshAppData
        if ($r.ok) { $created += $r.message }
    }
    return @($created)
}

function Invoke-SkillSetAppAlias {
    param(
        [Parameter(Mandatory)][string]$Spoken,
        [Parameter(Mandatory)][string]$Target,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    return Set-FreshAgentAppAlias -SpokenName $Spoken -TargetName $Target -FreshAppData $FreshAppData
}

function Invoke-SkillListAppAliases {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $apps = Get-FreshAgentSkillsAppsConfig -FreshAppData $FreshAppData
    $lines = @()
    if ($apps -and $apps.apps) {
        foreach ($p in $apps.apps.PSObject.Properties) {
            $al = @($p.Value.aliases) -join ', '
            $pathList = if ($p.Value.paths -is [string]) { @([string]$p.Value.paths) } else { @($p.Value.paths) }
            $path = if ($pathList.Count -gt 0) { [string]$pathList[0] } else { '' }
            $lines += ("{0}: [{1}] {2}" -f $p.Name, $al, $path)
        }
    }
    $userPath = Get-FreshAgentSkillsAppsUserPath -FreshAppData $FreshAppData
    $userNote = if (Test-Path -LiteralPath $userPath) { ' (user + defaults)' } else { ' (defaults)' }
    if ($lines.Count -eq 0) {
        return @{ ok = $true; message = "Aucun alias apps$userNote." }
    }
    $msg = "Aliases$($userNote): " + (($lines | Select-Object -First 12) -join ' | ')
    return @{ ok = $true; message = $msg }
}

function Show-FreshAgentAppInventoryHelp {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    Ensure-FreshAgentCommonAppAliases -FreshAppData $FreshAppData | Out-Null
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('Inventaire apps / alias Fresh Agent')
    [void]$lines.Add('Dis: "alias discord vers legcord" pour creer un alias.')
    [void]$lines.Add('')
    [void]$lines.Add('--- Aliases ---')
    $al = Invoke-SkillListAppAliases -FreshAppData $FreshAppData
    [void]$lines.Add([string]$al.message)
    [void]$lines.Add('')
    [void]$lines.Add('--- Start Menu (extrait) ---')
    $menu = @(Get-FreshAgentStartMenuCatalog | Sort-Object Name | Select-Object -First 25)
    foreach ($m in $menu) { [void]$lines.Add(('  {0}' -f $m.Name)) }
    [void]$lines.Add('')
    [void]$lines.Add('--- Installes / jeux (extrait) ---')
    $inst = @(Get-FreshAgentInstalledAppCatalog | Sort-Object Name | Select-Object -First 25)
    foreach ($m in $inst) { [void]$lines.Add(('  {0}' -f $m.Name)) }
    $text = $lines -join [Environment]::NewLine
    try {
        [System.Windows.Forms.MessageBox]::Show(
            $text,
            'Inventaire & aliases',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch { return $text }
}

function Test-FreshAgentCloseProcessNameMatch {
    param(
        [string]$ProcessName,
        [string[]]$Candidates
    )
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $false }
    foreach ($c in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$c)) { continue }
        $cand = [string]$c
        if ($ProcessName.Equals($cand, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        $pk = ConvertTo-FreshAgentAppCompactKey -Text $ProcessName
        $ck = ConvertTo-FreshAgentAppCompactKey -Text $cand
        if ([string]::IsNullOrWhiteSpace($ck) -or $ck.Length -lt 4) { continue }
        if ($pk -eq $ck) { return $true }
        # Prefix court (discord -> discordptb). Pas de Contains dans les deux sens.
        if ($ck.Length -ge 5 -and $pk.Length -gt $ck.Length -and $pk.StartsWith($ck) -and (($pk.Length - $ck.Length) -le 4)) {
            return $true
        }
    }
    return $false
}

function Get-FreshAgentCloseAppNameCandidates {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $list = New-Object System.Collections.Generic.List[string]
    $add = {
        param([string]$n)
        if ([string]::IsNullOrWhiteSpace($n)) { return }
        $t = $n.Trim()
        if (-not $list.Contains($t)) { [void]$list.Add($t) }
    }
    $resolved = $Name
    if (Get-Command Resolve-FreshAgentSpokenAppName -ErrorAction SilentlyContinue) {
        try {
            $r = Resolve-FreshAgentSpokenAppName -Name $Name -FreshAppData $FreshAppData
            if ($r) { $resolved = [string]$r }
        }
        catch { }
    }
    & $add $resolved
    & $add $Name
    if (Get-Command Get-FreshAgentSkillsAppsConfig -ErrorAction SilentlyContinue) {
        try {
            $apps = Get-FreshAgentSkillsAppsConfig -FreshAppData $FreshAppData
            $want = @(
                (ConvertTo-FreshAgentAppCompactKey -Text $Name),
                (ConvertTo-FreshAgentAppCompactKey -Text $resolved)
            ) | Where-Object { $_ }
            if ($apps -and $apps.apps) {
                foreach ($p in $apps.apps.PSObject.Properties) {
                    $cands = @($p.Name) + @($p.Value.aliases) + @($p.Value.process)
                    $hit = $false
                    foreach ($c in $cands) {
                        if (-not $c) { continue }
                        $ck = ConvertTo-FreshAgentAppCompactKey -Text ([string]$c)
                        if ($ck -and ($want -contains $ck)) { $hit = $true; break }
                    }
                    if (-not $hit) { continue }
                    & $add ([string]$p.Name)
                    if ($p.Value.process) { & $add ([string]$p.Value.process) }
                }
            }
        }
        catch { }
    }
    return @{
        resolvedName = $resolved
        candidates   = @($list)
    }
}

function Get-FreshAgentCloseAppTargets {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $info = Get-FreshAgentCloseAppNameCandidates -Name $Name -FreshAppData $FreshAppData
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Id -ne $PID -and (Test-FreshAgentCloseProcessNameMatch -ProcessName $_.ProcessName -Candidates $info.candidates)
        })
    $msg = ''
    if ($procs.Count -eq 0) { $msg = "Aucun process pour: $Name" }
    return @{
        resolvedName = [string]$info.resolvedName
        candidates   = @($info.candidates)
        processes    = @($procs | Select-Object Id, ProcessName)
        message      = $msg
    }
}

function Invoke-SkillCloseApp {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $preview = Get-FreshAgentCloseAppTargets -Name $Name -FreshAppData $FreshAppData
    $procs = @($preview.processes)
    if ($procs.Count -eq 0) {
        return @{
            ok      = $false
            message = [string]$preview.message
            spoken  = ("{0} n'est pas ouvert." -f $Name)
        }
    }
    $killed = @()
    foreach ($p in $procs) {
        $live = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        if (-not $live) { continue }
        if (-not (Test-FreshAgentCloseProcessNameMatch -ProcessName $live.ProcessName -Candidates $preview.candidates)) { continue }
        try {
            Stop-Process -Id $live.Id -Force -ErrorAction Stop
            $killed += ('{0} ({1})' -f $live.ProcessName, $live.Id)
        }
        catch { }
    }
    if ($killed.Count -eq 0) {
        return @{ ok = $false; message = "Echec fermeture: $Name" }
    }
    $closed = (($killed | Select-Object -Unique) -join ', ')
    $who = if ($preview.resolvedName) { [string]$preview.resolvedName } else { $Name }
    return @{
        ok      = $true
        message = ("Ferme: {0}" -f $closed)
        spoken  = ("{0} est ferme ({1})." -f $who, $closed)
    }
}

function Ensure-FreshAgentMediaKeysType {
    if ('FreshAgentMediaKeys' -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class FreshAgentMediaKeys {
    public const byte VK_VOLUME_MUTE = 0xAD;
    public const byte VK_VOLUME_DOWN = 0xAE;
    public const byte VK_VOLUME_UP = 0xAF;
    public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    public static void Tap(byte vk) {
        keybd_event(vk, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
        keybd_event(vk, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
"@
}

function Set-FreshAgentVolume {
    param(
        [ValidateSet('up', 'down', 'mute', 'unmute', 'set')]
        [string]$Action = 'up',
        [int]$Level = -1
    )
    if ($Action -eq 'set' -and $Level -ge 0) {
        return @{
            ok      = $false
            message = 'Reglage volume absolu non disponible sans nircmd.'
            spoken  = 'Je ne peux pas regler le volume a un niveau precis pour le moment.'
        }
    }
    try {
        Ensure-FreshAgentMediaKeysType
        $vk = switch ($Action) {
            'up' { [FreshAgentMediaKeys]::VK_VOLUME_UP }
            'down' { [FreshAgentMediaKeys]::VK_VOLUME_DOWN }
            'mute' { [FreshAgentMediaKeys]::VK_VOLUME_MUTE }
            'unmute' { [FreshAgentMediaKeys]::VK_VOLUME_MUTE }
            default { [FreshAgentMediaKeys]::VK_VOLUME_UP }
        }
        if ($Action -eq 'unmute') {
            # Volume+ demute Windows, Volume- annule le cran sans re-muter.
            [FreshAgentMediaKeys]::Tap([byte][FreshAgentMediaKeys]::VK_VOLUME_UP)
            Start-Sleep -Milliseconds 60
            [FreshAgentMediaKeys]::Tap([byte][FreshAgentMediaKeys]::VK_VOLUME_DOWN)
        }
        else {
            $times = if ($Action -eq 'up' -or $Action -eq 'down') { 5 } else { 1 }
            for ($i = 0; $i -lt $times; $i++) {
                [FreshAgentMediaKeys]::Tap([byte]$vk)
                Start-Sleep -Milliseconds 40
            }
        }
        $spoken = switch ($Action) {
            'mute' { 'Son coupe.' }
            'unmute' { 'Son reactive.' }
            'up' { 'Volume augmente.' }
            'down' { 'Volume baisse.' }
            default { "Volume: $Action" }
        }
        return @{ ok = $true; message = "Volume: $Action"; spoken = $spoken }
    }
    catch {
        return @{ ok = $false; message = $_.Exception.Message; spoken = 'Impossible de regler le volume.' }
    }
}

function ConvertTo-FreshAgentSettingsPageKey {
    param([string]$Page = '')
    if ([string]::IsNullOrWhiteSpace($Page)) { return 'home' }
    $p = $Page.Trim().ToLowerInvariant()
    try {
        $formD = $p.Normalize([Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $formD.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($ch)
            }
        }
        $p = $sb.ToString()
    }
    catch { }
    $p = $p -replace '\s+', ' '
    $p = $p -replace "^(de |du |des |d'|d )", ''
    $p = $p.Trim()
    switch -Regex ($p) {
        '^(home|accueil)?$' { return 'home' }
        '^(son|audio|volume|micros?|sound)$' { return 'sound' }
        '^(affichage|ecran|moniteur|display)$' { return 'display' }
        '^(wifi|wi-fi|wi fi|reseau|internet|ethernet|network)$' { return 'network' }
        '^bluetooth$' { return 'bluetooth' }
        '^(confidentialite|vie privee|privacy)$' { return 'privacy' }
        '^(mises? a jour|windows update|windowsupdate|update|maj)$' { return 'update' }
        '^(alimentation|veille|batterie|power)$' { return 'power' }
        '^(personnalisation|theme|personalization)$' { return 'personalization' }
        '^(applications?|apps?)$' { return 'apps' }
        default { return 'home' }
    }
}

function Open-FreshAgentWindowsSettings {
    param([string]$Page = 'home')
    $key = ConvertTo-FreshAgentSettingsPageKey -Page $Page
    $uri = switch ($key) {
        'sound' { 'ms-settings:sound' }
        'display' { 'ms-settings:display' }
        'network' { 'ms-settings:network' }
        'bluetooth' { 'ms-settings:bluetooth' }
        'privacy' { 'ms-settings:privacy' }
        'update' { 'ms-settings:windowsupdate' }
        'power' { 'ms-settings:powersleep' }
        'personalization' { 'ms-settings:personalization' }
        'apps' { 'ms-settings:appsfeatures' }
        default { 'ms-settings:' }
    }
    Start-Process $uri
    return @{ ok = $true; message = "Reglages: $key" }
}

function Set-FreshAgentWindowsTheme {
    param([ValidateSet('light', 'dark')][string]$Theme)
    $apps = if ($Theme -eq 'light') { 1 } else { 0 }
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    try {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        Set-ItemProperty -Path $path -Name 'AppsUseLightTheme' -Value $apps -Type DWord
        Set-ItemProperty -Path $path -Name 'SystemUsesLightTheme' -Value $apps -Type DWord
        return @{ ok = $true; message = "Theme $Theme active." }
    }
    catch {
        return @{ ok = $false; message = $_.Exception.Message }
    }
}

function Set-FreshAgentPowerPlan {
    param([ValidateSet('balanced', 'high', 'power_saver', 'ultimate')][string]$Plan = 'balanced')
    $guid = switch ($Plan) {
        'balanced' { '381b4222-f694-41f0-9685-ff5bb260df2e' }
        'high' { '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
        'power_saver' { 'a1841308-3541-4fab-bc81-f71556f20b4a' }
        'ultimate' {
            if (Get-Command Ensure-UltimatePerformanceActive -ErrorAction SilentlyContinue) {
                Ensure-UltimatePerformanceActive | Out-Null
                return @{ ok = $true; message = 'Plan Ultimate Performance.' }
            }
            '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        }
    }
    try {
        powercfg /setactive $guid | Out-Null
        return @{ ok = $true; message = "Plan alimentation: $Plan" }
    }
    catch {
        return @{ ok = $false; message = $_.Exception.Message }
    }
}

function Invoke-FreshAgentSystemPower {
    param([ValidateSet('lock', 'sleep', 'restart', 'shutdown')][string]$Action)
    switch ($Action) {
        'lock' {
            rundll32.exe user32.dll,LockWorkStation
            return @{ ok = $true; message = 'Session verrouillee.' }
        }
        'sleep' {
            rundll32.exe powrprof.dll,SetSuspendState 0,1,0
            return @{ ok = $true; message = 'Mise en veille.' }
        }
        'restart' {
            shutdown.exe /r /t 5 /c 'Fresh Agent'
            return @{ ok = $true; message = 'Redemarrage dans 5 s.' }
        }
        'shutdown' {
            shutdown.exe /s /t 5 /c 'Fresh Agent'
            return @{ ok = $true; message = 'Extinction dans 5 s.' }
        }
    }
}

function Invoke-FreshAgentWingetUpgrade {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        return @{ ok = $false; message = 'winget introuvable.' }
    }
    Start-Process -FilePath $winget.Source -ArgumentList @('upgrade', '--all', '--accept-package-agreements', '--accept-source-agreements') -WindowStyle Normal
    return @{ ok = $true; message = 'winget upgrade lance.' }
}

function Invoke-FreshAgentWinUtilMaintenance {
    # Prefer existing launcher path if present
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'FreshWindows\Start-FreshWindows.cmd'),
        (Join-Path $env:LOCALAPPDATA 'FreshWindows\launcher.ps1')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            if ($c -like '*.cmd') {
                Start-Process -FilePath $c
            }
            else {
                Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $c)
            }
            return @{ ok = $true; message = 'Maintenance Fresh Windows lancee.' }
        }
    }
    return @{ ok = $false; message = 'Launcher Fresh Windows introuvable.' }
}

# --- Skill handlers ---

function Invoke-SkillSetVolume {
    param([string]$Action = 'up', [int]$Level = -1)
    return Set-FreshAgentVolume -Action $Action -Level $Level
}

function Invoke-SkillOpenSettings {
    param([string]$Page = 'home')
    return Open-FreshAgentWindowsSettings -Page $Page
}

function Invoke-SkillSetTheme {
    param([string]$Theme = 'dark')
    return Set-FreshAgentWindowsTheme -Theme $Theme
}

function Invoke-SkillSetPowerPlan {
    param([string]$Plan = 'balanced')
    return Set-FreshAgentPowerPlan -Plan $Plan
}

function Invoke-SkillSystemPower {
    param([string]$Action = 'lock')
    return Invoke-FreshAgentSystemPower -Action $Action
}

function Invoke-SkillWingetUpgrade {
    return Invoke-FreshAgentWingetUpgrade
}

function Invoke-SkillWinUtilMaintenance {
    return Invoke-FreshAgentWinUtilMaintenance
}
