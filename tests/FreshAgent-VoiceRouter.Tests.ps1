#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-VoiceRouter.ps1')

Describe 'FreshAgent VoiceRouter' {
    BeforeAll {
        $script:Tmp = Join-Path $env:TEMP ('FreshAgent-VoiceRouter-{0}' -f [guid]::NewGuid().ToString('N'))
        $routerDir = Join-Path $script:Tmp 'configs\skills\router'
        New-Item -ItemType Directory -Path $routerDir -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root 'configs\skills\router\fr-pc.json') -Destination (Join-Path $routerDir 'fr-pc.json') -Force
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
        $m.parameters.name | Should -Be 'Steam'
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
}
