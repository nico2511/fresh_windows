#Requires -Version 5.1
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-SttSettings.ps1')

Describe 'FreshAgent STT listen mode' {
    It 'prefers listenMode alwaysOn over pushToTalk true' {
        $cfg = [pscustomobject]@{
            stt = [pscustomobject]@{
                listenMode = 'alwaysOn'
                pushToTalk = $true
            }
        }
        Get-FreshAgentSttListenMode -AiConfig $cfg | Should -Be 'alwaysOn'
        Test-FreshAgentSttPushToTalkFromConfig -AiConfig $cfg | Should -Be $false
    }

    It 'maps pushToTalk false to alwaysOn when listenMode absent' {
        $cfg = [pscustomobject]@{
            stt = [pscustomobject]@{ pushToTalk = $false }
        }
        Get-FreshAgentSttListenMode -AiConfig $cfg | Should -Be 'alwaysOn'
    }

    It 'alwaysOn timing clamps absurd silenceMs' {
        $stt = [pscustomobject]@{ silenceMs = 60000; maxRecordSeconds = 30 }
        $t = Get-FreshAgentSttHostTiming -Stt $stt -PushToTalk $false
        $t.silenceMs | Should -BeLessOrEqual 5000
        $t.silenceMs | Should -BeGreaterOrEqual 250
    }

    It 'PTT timing keeps long silence for hold-to-talk' {
        $stt = [pscustomobject]@{ silenceMs = 450; maxRecordSeconds = 6 }
        $t = Get-FreshAgentSttHostTiming -Stt $stt -PushToTalk $true
        $t.silenceMs | Should -Be 60000
        $t.maxRecordSeconds | Should -BeGreaterOrEqual 30
    }

    It 'filters scribe hallucination transcripts' {
        Test-FreshAgentVoiceHostTranscriptUseful -Text 'Scribe Scribe.' | Should -Be $false
        Test-FreshAgentVoiceHostTranscriptUseful -Text 'Comment va le PC ?' | Should -Be $true
    }

    It 'resolves model small over base when dir empty' {
        Resolve-FreshAgentSttModelSize -Requested 'base' -ModelsDir '' | Should -Be 'small'
    }
}
