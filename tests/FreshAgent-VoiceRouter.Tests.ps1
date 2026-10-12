#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'FreshAgent VoiceRouter' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        . (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
        . (Join-Path $root 'scripts\lib\FreshAgent-VoiceRouter.ps1')
        . (Join-Path $root 'scripts\lib\FreshAgent-WindowsActions.ps1')

        $script:Tmp = Join-Path $env:TEMP ('FreshAgent-VoiceRouter-{0}' -f [guid]::NewGuid().ToString('N'))
        $routerDir = Join-Path $script:Tmp 'configs\skills\router'
        New-Item -ItemType Directory -Path $routerDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'configs\skills\router\fr-pc.json') -Destination (Join-Path $routerDir 'fr-pc.json') -Force
        $appsDir = Join-Path $script:Tmp 'configs'
        Copy-Item -LiteralPath (Join-Path $root 'configs\skills-apps.json') -Destination (Join-Path $appsDir 'skills-apps.json') -Force

        # Force la reecriture "ouvre X" -> "lance X" pour verifier qu'elle reste un dernier recours.
        function script:Resolve-FreshAgentSpokenAppName {
            param([string]$Name, [string]$FreshAppData)
            return $Name
        }
    }

    AfterAll {
        if ($script:Tmp -and (Test-Path -LiteralPath $script:Tmp)) {
            Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Normalizes accents and punctuation' {
        $etat = ([string][char]0x00C9) + 'tat du syst' + ([string][char]0x00E8) + 'me.'
        $n = ConvertTo-FreshAgentVoiceNormalized -Text $etat
        $n | Should -Be 'etat du systeme'
    }

    It 'Matches Whisper-like: Etat du systeme with accents and period' {
        $etat = ([string][char]0x00C9) + 'tat du syst' + ([string][char]0x00E8) + 'me.'
        $m = Resolve-FreshAgentVoiceRouterMatch -Transcript $etat -FreshAppData $script:Tmp
        $m.matched | Should -Be $true
        $m.skillId | Should -Be 'check_system_health'
    }

    It 'Matches Whisper-like: Lance Steam' {
        $m = Resolve-FreshAgentVoiceRouterMatch -Transcript 'Lance Steam' -FreshAppData $script:Tmp
        $m.matched | Should -Be $true
        $m.skillId | Should -Be 'launch_app'
        $m.parameters.name | Should -Match '(?i)^steam$'
    }

    It 'Matches variants: lance steam!' {
        $m = Resolve-FreshAgentVoiceRouterMatch -Transcript 'lance steam!' -FreshAppData $script:Tmp
        $m.matched | Should -Be $true
        $m.skillId | Should -Be 'launch_app'
    }

    It 'Matches: Comment va le PC ?' {
        $m = Resolve-FreshAgentVoiceRouterMatch -Transcript 'Comment va le PC ?' -FreshAppData $script:Tmp
        $m.matched | Should -Be $true
        $m.skillId | Should -Be 'check_system_health'
    }

    It 'MatchOnly does not require skill engine' {
        $etat = ([string][char]0x00C9) + 'tat du syst' + ([string][char]0x00E8) + 'me.'
        $r = Invoke-FreshAgentVoiceRouter -Transcript $etat -FreshAppData $script:Tmp -MatchOnly
        $r.matched | Should -Be $true
        $r.skillId | Should -Be 'check_system_health'
        $r.execute | Should -Be $false
    }

    It 'ouvre les parametres is open_settings, not launch_app' {
        $parametres = 'param' + ([string][char]0x00E8) + 'tres'
        $phrase = 'Ouvre les ' + $parametres + '.'
        $m = Resolve-FreshAgentVoiceRouterMatch -Transcript $phrase -FreshAppData $script:Tmp
        $m.matched | Should -Be $true
        $m.skillId | Should -Be 'open_settings'
        $m.skillId | Should -Not -Be 'launch_app'
    }

    It 'ouvre les parametres son maps the page token' {
        $parametres = 'param' + ([string][char]0x00E8) + 'tres'
        $phrase = 'Ouvre les ' + $parametres + ' son.'
        $m = Resolve-FreshAgentVoiceRouterMatch -Transcript $phrase -FreshAppData $script:Tmp
        $m.skillId | Should -Be 'open_settings'
        $m.parameters.Page | Should -Be 'son'
        ConvertTo-FreshAgentSettingsPageKey -Page $m.parameters.Page | Should -Be 'sound'
    }

    It 'French settings pages map to ms-settings keys' {
        ConvertTo-FreshAgentSettingsPageKey -Page 'son' | Should -Be 'sound'
        ConvertTo-FreshAgentSettingsPageKey -Page 'affichage' | Should -Be 'display'
        ConvertTo-FreshAgentSettingsPageKey -Page 'wifi' | Should -Be 'network'
        $reseau = 'r' + ([string][char]0x00E9) + 'seau'
        ConvertTo-FreshAgentSettingsPageKey -Page $reseau | Should -Be 'network'
        ConvertTo-FreshAgentSettingsPageKey -Page 'bluetooth' | Should -Be 'bluetooth'
        ConvertTo-FreshAgentSettingsPageKey -Page 'mises a jour' | Should -Be 'update'
        $mises = 'mises ' + ([string][char]0x00E0) + ' jour'
        ConvertTo-FreshAgentSettingsPageKey -Page $mises | Should -Be 'update'
        ConvertTo-FreshAgentSettingsPageKey -Page 'du son' | Should -Be 'sound'
    }

    It 'ouvre YouTube X is youtube_search, not launch_app' {
        $m = Resolve-FreshAgentVoiceRouterMatch -Transcript 'Ouvre YouTube lofi chill.' -FreshAppData $script:Tmp
        $m.matched | Should -Be $true
        $m.skillId | Should -Be 'youtube_search'
        $m.parameters.query | Should -Match '(?i)lofi'
    }

    It 'keeps URL punctuation for open_url' {
        $m = Resolve-FreshAgentVoiceRouterMatch -Transcript 'Ouvre https://example.com.' -FreshAppData $script:Tmp
        $m.matched | Should -Be $true
        $m.skillId | Should -Be 'open_url'
        $m.parameters.url | Should -Be 'https://example.com'
    }

    It 'remets le son unmutes' {
        $reactive = 'R' + ([string][char]0x00E9) + 'active le son.'
        foreach ($phrase in @('Remets le son.', 'remet le son', $reactive)) {
            $m = Resolve-FreshAgentVoiceRouterMatch -Transcript $phrase -FreshAppData $script:Tmp
            $m.skillId | Should -Be 'set_volume'
            $m.parameters.Action | Should -Be 'unmute'
        }
    }

    It 'power plan voice: performances, equilibre, economie' {
        $eq = ([string][char]0x00E9) + 'quilibr' + ([string][char]0x00E9)
        $eco = ([string][char]0x00E9) + 'conomie'
        $high = Resolve-FreshAgentVoiceRouterMatch -Transcript 'Passe en mode performances.' -FreshAppData $script:Tmp
        $high.skillId | Should -Be 'set_power_plan'
        $high.parameters.Plan | Should -Be 'high'
        $bal = Resolve-FreshAgentVoiceRouterMatch -Transcript ('Passe en ' + $eq + '.') -FreshAppData $script:Tmp
        $bal.skillId | Should -Be 'set_power_plan'
        $bal.parameters.Plan | Should -Be 'balanced'
        $saver = Resolve-FreshAgentVoiceRouterMatch -Transcript ('Mode ' + $eco + '.') -FreshAppData $script:Tmp
        $saver.skillId | Should -Be 'set_power_plan'
        $saver.parameters.Plan | Should -Be 'power_saver'
    }
}
