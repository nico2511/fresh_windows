#Requires -Version 5.1
<#
  Router vocal FR : transcript -> skills (sans Ollama).
  Pas de dictionnaire de coquilles Whisper: normalisation + segmentation +
  resolution floue des apps (Start Menu / skills-apps) apres le verbe d'action.
#>

function Get-FreshAgentVoiceRouterRules {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $local = Join-Path $FreshAppData 'configs\skills\router\fr-pc.json'
    if (-not (Test-Path -LiteralPath $local)) {
        return @{ rules = @() }
    }
    try {
        return (Get-Content -LiteralPath $local -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return @{ rules = @() }
    }
}

function ConvertFrom-FreshAgentVoicePatternExample {
    <# Transforme un pattern regex router en exemple lisible. #>
    param([string]$Pattern)
    if ([string]::IsNullOrWhiteSpace($Pattern)) { return '' }
    $p = $Pattern.Trim()
    $p = $p -replace '^\^', '' -replace '\$$', ''
    # Groupes optionnels (?:le\s+)? -> ignore (exemple plus court)
    $p = [regex]::Replace($p, '\(\?\:[^)]+\)\?', '')
    $p = [regex]::Replace($p, '\([^)]+\)\?', '')
    # (?:a|b|c) ou (a|b) -> premier choix
    for ($i = 0; $i -lt 12; $i++) {
        $m = [regex]::Match($p, '\(\?\:([^|()]+)(?:\|[^)]*)\)|\(([^|()]+)(?:\|[^)]*)\)')
        if (-not $m.Success) { break }
        $pick = if ($m.Groups[1].Success -and $m.Groups[1].Value) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        $p = $p.Remove($m.Index, $m.Length).Insert($m.Index, $pick)
    }
    $p = $p -replace '\\s\+', ' '
    $p = $p -replace '\\s\*', ' '
    $p = $p -replace '\(\.\+\)', '<...>'
    $p = $p -replace '\(\.\*\)', '<...>'
    $p = $p -replace "\[''`']", "'"
    $p = $p -replace '[\\\(\)\?\*\+\^\$\[\]\|]', ''
    $p = $p -replace '\s+', ' '
    return $p.Trim()
}

function Get-FreshAgentVoiceCommandHelpLines {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $pack = Get-FreshAgentVoiceRouterRules -FreshAppData $FreshAppData
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('Commandes vocales / texte (skills)')
    [void]$lines.Add('Parle apres Ecoute ON, ou tape dans le champ IA.')
    [void]$lines.Add('')
    foreach ($rule in @($pack.rules)) {
        if (-not $rule.enabled) { continue }
        $sid = [string]$rule.skillId
        if ($sid -like '__confirm*') { continue }
        $label = if ($rule.say) { [string]$rule.say } else { $sid }
        $examples = @()
        foreach ($pat in @($rule.patterns)) {
            $ex = ConvertFrom-FreshAgentVoicePatternExample -Pattern ([string]$pat)
            if ($ex -and $examples -notcontains $ex) { $examples += $ex }
            if ($examples.Count -ge 2) { break }
        }
        if ($examples.Count -eq 0) { continue }
        [void]$lines.Add(("{0}  ->  {1}" -f ($examples -join ' | '), $label))
    }
    [void]$lines.Add('')
    [void]$lines.Add('Exemples utiles:')
    [void]$lines.Add('  lance Steam  |  lance Grok Bot  |  lance Battlefield 6')
    [void]$lines.Add('  ferme Discord  |  mode jeu  |  recherche prix carburant')
    [void]$lines.Add('  alias discord vers legcord  (habitude vocale -> app reelle)')
    [void]$lines.Add('  liste aliases  |  oui / annule (apres confirmation)')
    return @($lines)
}

function Show-FreshAgentVoiceCommandsHelp {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    $lines = @(Get-FreshAgentVoiceCommandHelpLines -FreshAppData $FreshAppData)
    $text = $lines -join [Environment]::NewLine
    try {
        [System.Windows.Forms.MessageBox]::Show(
            $text,
            'Aide — commandes Fresh Agent',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    catch {
        # Hors UI: renvoyer le texte
        return $text
    }
}

function ConvertTo-FreshAgentVoiceNormalized {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.Trim().ToLowerInvariant()
    $t = $t -replace "[`'`’]", "'"
    # Strip diacritics: "état" -> "etat"
    try {
        $formD = $t.Normalize([Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $formD.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$sb.Append($ch)
            }
        }
        $t = $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
    }
    catch { }
    # Drop punctuation (keep letters, digits, spaces, apostrophe)
    $t = [regex]::Replace($t, "[^\p{L}\p{Nd}\s']+", ' ')
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Repair-FreshAgentVoiceTranscript {
    <#
      Structure seulement: apostrophes / verbe colle + cible resolue via catalogue apps.
      Ex: "lancetime" -> "lance steam" si "steam" est le meilleur match flou de "time".
      Ex: "l'ancestime" -> meme logique. Pas de liste hardcodee par app.
    #>
    param(
        [string]$Text,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $t = ConvertTo-FreshAgentVoiceNormalized -Text $Text
    if ([string]::IsNullOrWhiteSpace($t)) { return $t }

    $t = $t -replace "\bl\s+ance\b", 'lance'
    $t = $t -replace "\bl'\s*ance\b", 'lance'
    $t = $t -replace "\bl'ance", 'lance'
    # Whisper FR: "L'auce steam" / "L'oss" proches de "lance"
    $t = $t -replace "\bl'auce\b", 'lance'
    $t = $t -replace "\blauce\b", 'lance'
    $t = $t -replace "\bn'?etoyage\b", 'nettoyage'
    # Imperatif Whisper: "Lancez / Ouvrez / Demarrez X" (sinon aucun skill ne matche)
    $t = $t -replace '\blancez\b', 'lance'
    $t = $t -replace '\blancer\b', 'lance'
    $t = $t -replace '\bouvrez\b', 'ouvre'
    $t = $t -replace '\bouvrir\b', 'ouvre'
    $t = $t -replace '\bdemarrez\b', 'demarre'
    $t = $t -replace '\bdemarrer\b', 'demarre'
    $t = $t -replace '\bfermez\b', 'ferme'
    $t = $t -replace '\bfermer\b', 'ferme'
    $t = $t -replace '\bquittez\b', 'quitte'
    $t = $t -replace '\bquitter\b', 'quitte'
    $t = $t -replace '\barretez\b', 'arrete'
    $t = $t -replace '\barreter\b', 'arrete'
    # Bloc-notes mal entendu
    $t = $t -replace '\bbloc\s*[- ]?\s*nets?\b', 'bloc notes'
    $t = $t -replace '\bbloc\s*[- ]?\s*note\b', 'bloc notes'
    # Volume: "Coupsons !" / "coupezon" (Whisper colle les mots)
    $t = $t -replace '\bcoupsons\b', 'coupe son'
    $t = $t -replace '\bcoupons\b', 'coupe son'
    $t = $t -replace '\bcoupez?\s+sons?\b', 'coupe son'
    $t = $t -replace '\bmutes?\b', 'mute'
    # Whisper: "Sibir Scribe" -> CyberScribe (meme famille phonetique)
    if ($t -match 'scribe') {
        $t = $t -replace '\bsibir\b', 'cyber'
        $t = $t -replace '\bsiber\b', 'cyber'
        $t = $t -replace '\bciber\b', 'cyber'
    }
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()

    $verbs = 'lance|lancer|lancez|ouvre|ouvrir|ouvrez|demarre|demarrer|demarrez'
    # Verbe + reste deja separe
    $m = [regex]::Match($t, "^(?:$verbs)\s+(.+)$", 'IgnoreCase')
    if ($m.Success -and (Get-Command Resolve-FreshAgentSpokenAppName -ErrorAction SilentlyContinue)) {
        $spoken = $m.Groups[1].Value.Trim()
        $resolved = Resolve-FreshAgentSpokenAppName -Name $spoken -FreshAppData $FreshAppData
        if ($resolved -and $resolved -ne $spoken) {
            return ('lance {0}' -f $resolved.ToLowerInvariant())
        }
        return ('lance {0}' -f $spoken)
    }

    # Verbe colle a la cible: lancetime / lancegrokbot / ouvrirchrome
    $glued = [regex]::Match($t, '^(?:lance|lancer|lancez|ouvre|ouvrir|ouvrez|demarre|demarrer|demarrez)([a-z0-9]{2,})$', 'IgnoreCase')
    if (-not $glued.Success) {
        $glued = [regex]::Match($t, "^l'?ance([a-z0-9]{2,})$", 'IgnoreCase')
    }
    if ($glued.Success -and (Get-Command Resolve-FreshAgentSpokenAppName -ErrorAction SilentlyContinue)) {
        $tail = $glued.Groups[1].Value
        $resolved = Resolve-FreshAgentSpokenAppName -Name $tail -FreshAppData $FreshAppData
        if ($resolved) {
            return ('lance {0}' -f $resolved.ToLowerInvariant())
        }
    }

    return $t
}

function Get-FreshAgentVoiceTranscriptCandidates {
    param(
        [string]$Transcript,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $raw = ConvertTo-FreshAgentVoiceNormalized -Text $Transcript
    $fixed = Repair-FreshAgentVoiceTranscript -Text $Transcript -FreshAppData $FreshAppData
    $list = New-Object System.Collections.Generic.List[string]
    $add = {
        param([string]$s)
        if ([string]::IsNullOrWhiteSpace($s)) { return }
        $s = $s.Trim()
        if ($s.Length -lt 3) { return }
        if (-not $list.Contains($s)) { [void]$list.Add($s) }
    }

    # 1) Segments court d'abord
    foreach ($base in @($fixed, $raw)) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        foreach ($seg in @([regex]::Split($base, '\s*(?:[.!?;]+|\bet\b|\bpuis\b)\s+'))) {
            & $add (Repair-FreshAgentVoiceTranscript -Text $seg -FreshAppData $FreshAppData)
        }
    }
    # 2) Sous-match "lance X"
    foreach ($base in @($fixed, $raw)) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $mm = [regex]::Match($base, '(?:lance|lancer|lancez|ouvre|ouvrir|ouvrez|demarre|demarrer|demarrez)\s+(.+)$', 'IgnoreCase')
        if ($mm.Success) {
            $appPart = $mm.Groups[1].Value.Trim()
            if (Get-Command Resolve-FreshAgentSpokenAppName -ErrorAction SilentlyContinue) {
                $appPart = Resolve-FreshAgentSpokenAppName -Name $appPart -FreshAppData $FreshAppData
            }
            & $add ('lance {0}' -f $appPart.ToLowerInvariant())
        }
    }
    # 3) Phrase complete
    & $add $fixed
    & $add $raw
    return @($list)
}

function Resolve-FreshAgentVoiceRouterMatch {
    param(
        [Parameter(Mandatory)][string]$Transcript,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $candidates = @(Get-FreshAgentVoiceTranscriptCandidates -Transcript $Transcript -FreshAppData $FreshAppData)
    if ($candidates.Count -eq 0) {
        return @{ ok = $false; matched = $false; message = 'Vide' }
    }

    $pack = Get-FreshAgentVoiceRouterRules -FreshAppData $FreshAppData
    $rules = @($pack.rules)
    foreach ($norm in $candidates) {
        foreach ($rule in $rules) {
            if (-not $rule.enabled) { continue }
            $patterns = @($rule.patterns)
            $hit = $false
            $m = $null
            foreach ($pat in $patterns) {
                if ([string]::IsNullOrWhiteSpace($pat)) { continue }
                $m = [regex]::Match($norm, [string]$pat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                if ($m.Success) { $hit = $true; break }
            }
            if (-not $hit) { continue }

            $skillId = [string]$rule.skillId
            $params = @{}
            if ($rule.parameters) {
                foreach ($p in $rule.parameters.PSObject.Properties) {
                    $val = [string]$p.Value
                    if ($m -and $val -match '\$(\d+)') {
                        $val = [regex]::Replace($val, '\$(\d+)', {
                                param($mm)
                                $idx = [int]$mm.Groups[1].Value
                                if ($idx -lt $m.Groups.Count) { return $m.Groups[$idx].Value.Trim() }
                                return ''
                            })
                    }
                    $params[$p.Name] = $val
                }
            }

            # Resolution floue du parametre name (apps)
            if ($params.ContainsKey('name') -and $params.name -and (Get-Command Resolve-FreshAgentSpokenAppName -ErrorAction SilentlyContinue)) {
                $params.name = Resolve-FreshAgentSpokenAppName -Name ([string]$params.name) -FreshAppData $FreshAppData
            }

            $msg = if ($rule.say) { [string]$rule.say } else { "OK: $skillId" }
            return @{
                ok         = $true
                matched    = $true
                skillId    = $skillId
                message    = $msg
                say        = $msg
                parameters = $params
                execute    = $false
                matchedOn  = $norm
            }
        }
    }

    return @{
        ok      = $false
        matched = $false
        message = 'Commande non reconnue'
    }
}

function Invoke-FreshAgentVoiceRouter {
    param(
        [Parameter(Mandatory)][string]$Transcript,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main',
        [switch]$MatchOnly
    )
    $match = Resolve-FreshAgentVoiceRouterMatch -Transcript $Transcript -FreshAppData $FreshAppData
    if (-not $match.matched) { return $match }
    if ($MatchOnly) {
        $match.execute = $false
        return $match
    }

    $skillId = [string]$match.skillId
    $params = @{}
    if ($match.parameters -is [hashtable]) {
        $params = $match.parameters
    }
    elseif ($match.parameters) {
        foreach ($p in $match.parameters.PSObject.Properties) {
            $params[$p.Name] = $p.Value
        }
    }

    if (-not (Get-Command Invoke-FreshAgentSkill -ErrorAction SilentlyContinue)) {
        return @{ ok = $false; matched = $true; skillId = $skillId; message = 'Skills engine absent'; parameters = $params }
    }
    try {
        $result = Invoke-FreshAgentSkill -SkillId $skillId -Parameters $params -RepoRef $RepoRef -FreshAppData $FreshAppData
        return @{
            ok         = $true
            matched    = $true
            skillId    = $skillId
            message    = [string]$match.message
            result     = $result
            parameters = $params
            execute    = $true
        }
    }
    catch {
        return @{
            ok         = $false
            matched    = $true
            skillId    = $skillId
            message    = $_.Exception.Message
            parameters = $params
        }
    }
}
