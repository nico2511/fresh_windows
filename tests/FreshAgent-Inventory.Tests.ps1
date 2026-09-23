#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-Inventory.ps1')

Describe 'FreshAgent inventory' {
    It 'Build inventory json' {
        $tmp = Join-Path $env:TEMP ('FreshAgent-Inv-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $inv = Build-FreshAgentMachineInventory -FreshAppData $tmp
        $inv.defaultBrowser | Should -Not -BeNullOrEmpty
        (Test-Path -LiteralPath (Join-Path $tmp 'inventory.json')) | Should -Be $true
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}
