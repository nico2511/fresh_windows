#Requires -Version 5.1
<#
  Router vocal FR : transcript -> skills (sans Ollama).
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

function ConvertTo-FreshAgentVoiceNormalized {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.Trim().ToLowerInvariant()
    $t = $t -replace "[`'`’]", "'"
    $t = $t -replace '\s+', ' '
    return $t
}

function Invoke-FreshAgentVoiceRouter {
    param(
        [Parameter(Mandatory)][string]$Transcript,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = 'main'
    )
    $norm = ConvertTo-FreshAgentVoiceNormalized -Text $Transcript
    if ([string]::IsNullOrWhiteSpace($norm)) {
        return @{ ok = $false; matched = $false; message = 'Vide' }
    }

    $pack = Get-FreshAgentVoiceRouterRules -FreshAppData $FreshAppData
    $rules = @($pack.rules)
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

        if (-not (Get-Command Invoke-FreshAgentSkill -ErrorAction SilentlyContinue)) {
            return @{ ok = $false; matched = $true; skillId = $skillId; message = 'Skills engine absent' }
        }
        try {
            $result = Invoke-FreshAgentSkill -SkillId $skillId -Parameters $params -RepoRef $RepoRef -FreshAppData $FreshAppData
            $msg = if ($rule.say) { [string]$rule.say } else { "OK: $skillId" }
            return @{
                ok      = $true
                matched = $true
                skillId = $skillId
                message = $msg
                result  = $result
            }
        }
        catch {
            return @{
                ok      = $false
                matched = $true
                skillId = $skillId
                message = $_.Exception.Message
            }
        }
    }

    return @{
        ok      = $false
        matched = $false
        message = 'Commande non reconnue'
    }
}
