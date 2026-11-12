#Requires -Version 5.1
function Test-FreshWindowsPesterSuiteFailed {
    param($Result)
    $badCount = 0
    try { $badCount = [int]$Result.FailedCount } catch { $badCount = 1 }
    $resultName = ''
    try { $resultName = [string]$Result.Result } catch { $resultName = 'Failed' }
    if ($badCount -gt 0) { return $true }
    if ($resultName -eq 'Failed') { return $true }
    return $false
}
