#Requires -Version 5.1

Describe 'Run-AllTests aggregate (code partage)' {
    BeforeAll {
        $root = Split-Path $PSCommandPath -Parent
        . (Join-Path $root 'lib/FreshWindows-RunAggregate.ps1')
    }
    It 'echoue si Result Failed meme avec FailedCount 0' {
        $r = [pscustomobject]@{ FailedCount = 0; Result = 'Failed' }
        Test-FreshWindowsPesterSuiteFailed -Result $r | Should -Be $true
    }
    It 'reussit si Passed sans echec' {
        $r = [pscustomobject]@{ FailedCount = 0; Result = 'Passed' }
        Test-FreshWindowsPesterSuiteFailed -Result $r | Should -Be $false
    }
    It 'echoue si FailedCount > 0' {
        $r = [pscustomobject]@{ FailedCount = 2; Result = 'Passed' }
        Test-FreshWindowsPesterSuiteFailed -Result $r | Should -Be $true
    }
}
