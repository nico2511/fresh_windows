#Requires -Version 5.1
<#
  Lance Validate-Configs + Pester (si module disponible).
  Exit 0 = OK, 1 = echec.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSCommandPath -Parent
$failed = 0

Write-Host "=== Validate-Configs ===" -ForegroundColor Cyan
& (Join-Path $root 'Validate-Configs.ps1')
if ($LASTEXITCODE -ne 0) { $failed++ }

Write-Host "`n=== Validate-SkillsRegistry ===" -ForegroundColor Cyan
& (Join-Path $root 'Validate-SkillsRegistry.ps1')
if ($LASTEXITCODE -ne 0) { $failed++ }

Write-Host "`n=== Parse-Scripts ===" -ForegroundColor Cyan
& (Join-Path $root 'Parse-Scripts.ps1')
if ($LASTEXITCODE -ne 0) { $failed++ }

Write-Host "`n=== Smoke-VoiceHealth ===" -ForegroundColor Cyan
& (Join-Path $root 'Smoke-VoiceHealth.ps1')
if ($LASTEXITCODE -ne 0) { $failed++ }

$pesterMods = @(Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version -ge [version]'5.0' -and $_.Version -lt [version]'6.0' })
$pesterMod = $pesterMods | Where-Object { $_.Version -eq [version]'5.6.1' } | Select-Object -First 1
if (-not $pesterMod) {
    $pesterMod = $pesterMods | Sort-Object Version -Descending | Select-Object -First 1
}
if ($pesterMod) {
    Write-Host "`n=== Pester $($pesterMod.Version) ===" -ForegroundColor Cyan
    Import-Module Pester -RequiredVersion $pesterMod.Version -Force -ErrorAction Stop
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = Join-Path $root 'Launcher-Core.Tests.ps1'
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = 'Detailed'

    $pesterFiles = @(
        'Launcher-Core.Tests.ps1',
        'FreshAgent-OllamaBridge.Tests.ps1',
        'FreshAgent-Inventory.Tests.ps1',
        'FreshAgent-Rag.Tests.ps1',
        'FreshAgent-Config.Tests.ps1',
        'FreshAgent-VoiceRouter.Tests.ps1',
        'FreshAgent-Health.Tests.ps1',
        'FreshAgent-Safety.Tests.ps1',
        'Appx-Bloatware.Tests.ps1',
        'Windows-Stt.Tests.ps1',
        'FreshWindows-BackgroundAudit.Tests.ps1'
    )
    foreach ($pesterFile in $pesterFiles) {
        $path = Join-Path $root $pesterFile
        if (-not (Test-Path -LiteralPath $path)) { continue }
        Write-Host "`n=== Pester $pesterFile ===" -ForegroundColor Cyan
        $pesterConfig.Run.Path = $path
        $result = Invoke-Pester -Configuration $pesterConfig
        # Sans PassThru, Invoke-Pester (Pester 5) renvoie $null et le job reste vert.
        if ($null -eq $result) {
            Write-Host "Pester n'a pas renvoye de resultat pour $pesterFile." -ForegroundColor Red
            $failed++
            continue
        }
        $badCount = 0
        try { $badCount = [int]$result.FailedCount } catch { $badCount = 1 }
        $resultName = ''
        try { $resultName = [string]$result.Result } catch { }
        if ($badCount -gt 0 -or $resultName -eq 'Failed') { $failed++ }
    }
}
else {
    Write-Host "`nPester 5.x introuvable - les tests ne sont pas ignores." -ForegroundColor Red
    $failed++
}

if ($failed -gt 0) {
    Write-Host "`n$failed suite(s) en échec." -ForegroundColor Red
    exit 1
}
Write-Host "`nTous les tests OK." -ForegroundColor Green
exit 0
