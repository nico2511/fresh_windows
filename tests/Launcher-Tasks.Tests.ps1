#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Launcher-Tasks scheduled triggers' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        . (Join-Path $root 'scripts\lib\Launcher-Tasks.ps1')
    }

    It 'Get-FreshWindowsScheduledTaskLocalStartBoundary est sans offset fuseau' {
        $bound = Get-FreshWindowsScheduledTaskLocalStartBoundary -At '12:00'
        $bound | Should -Match '^\d{4}-\d{2}-\d{2}T12:00:00$'
        $bound | Should -Not -Match 'T\d{2}:\d{2}:\d{2}[Z+-]'
    }

    It 'Set-FreshWindowsScheduledTaskTriggerLocalTime reecrit StartBoundary' {
        $trigger = New-ScheduledTaskTrigger -Daily -At '12:00'
        $trigger.StartBoundary | Should -Not -BeNullOrEmpty
        $fixed = Set-FreshWindowsScheduledTaskTriggerLocalTime -Trigger $trigger -At '12:30'
        $fixed.StartBoundary | Should -Match 'T12:30:00$'
        $fixed.StartBoundary | Should -Not -Match ':\d{2}:\d{2}\+'
    }
}
