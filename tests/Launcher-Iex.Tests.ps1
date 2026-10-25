#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'launcher.ps1 (irm | iex)' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        $script:LauncherPath = Join-Path $root 'launcher.ps1'
    }

    It 'ne commence pas par un BOM UTF-8' {
        $bytes = [System.IO.File]::ReadAllBytes($script:LauncherPath)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasBom | Should -Be $false
    }

    It 'premiere ligne executable est #Requires -RunAsAdministrator' {
        $first = (Get-Content -LiteralPath $script:LauncherPath -TotalCount 1 -Encoding UTF8)
        $first.Trim() | Should -Be '#Requires -RunAsAdministrator'
    }

    It 'Write-Host n''utilise pas de caracteres non-ASCII' {
        $lines = Get-Content -LiteralPath $script:LauncherPath -Encoding UTF8
        $bad = @()
        foreach ($line in $lines) {
            if ($line -notmatch 'Write-Host') { continue }
            foreach ($ch in $line.ToCharArray()) {
                if ([int][char]$ch -gt 127) {
                    $bad += $line
                    break
                }
            }
        }
        $bad | Should -BeNullOrEmpty
    }
}
