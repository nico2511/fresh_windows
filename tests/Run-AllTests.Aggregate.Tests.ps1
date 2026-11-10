#Requires -Version 5.1

Describe 'Run-AllTests aggregate' {
    BeforeAll {
        function script:Test-FreshWindowsPesterSuiteFailed {
            param($Result)
            $badCount = 0
            try { $badCount = [int]$Result.FailedCount } catch { $badCount = 1 }
            $resultName = ''
            try { $resultName = [string]$Result.Result } catch { $resultName = 'Failed' }
            if ($badCount -gt 0) { return $true }
            if ($resultName -eq 'Failed') { return $true }
            return $false
        }
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
