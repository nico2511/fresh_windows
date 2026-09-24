#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-GameSession.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-SkillHandlers.ps1')
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-SkillCheckSystemHealth
$sw.Stop()
if (-not $r.ok) { throw 'Health skill not ok' }
if ($sw.Elapsed.TotalSeconds -gt 15) { throw ("Health trop lent: {0}s" -f $sw.Elapsed.TotalSeconds) }
Write-Host ("OK health in {0}ms: {1}" -f $sw.ElapsedMilliseconds, $r.message)
