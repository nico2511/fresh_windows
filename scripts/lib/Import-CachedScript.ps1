#Requires -Version 5.1
<#
  Télécharge un script GitHub dans %LOCALAPPDATA%\FreshWindows si ref change ou fichier absent.
  Retourne le chemin local (sans dot-source).
#>
function Get-FreshWindowsCachedScriptPath {
    param(
        [Parameter(Mandatory)][string]$CacheFileName,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$RepoRawRoot,
        [Parameter(Mandatory)][string]$RepoRef,
        [Parameter(Mandatory)][string]$FreshAppData,
        [switch]$ForceRefresh
    )

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $dest = Join-Path $FreshAppData $CacheFileName
    $meta = Join-Path $FreshAppData "$CacheFileName.ref"
    $url  = "$RepoRawRoot/$RemotePath"

    $needFetch = $ForceRefresh -or -not (Test-Path -LiteralPath $dest)
    if (-not $needFetch -and (Test-Path -LiteralPath $meta)) {
        try {
            $savedRef = (Get-Content -LiteralPath $meta -Raw -Encoding UTF8).Trim()
            if ($savedRef -ne $RepoRef) { $needFetch = $true }
        }
        catch { $needFetch = $true }
    }
    elseif (-not (Test-Path -LiteralPath $meta)) {
        $needFetch = $true
    }

    if ($needFetch) {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Set-Content -LiteralPath $meta -Value $RepoRef -Encoding UTF8 -NoNewline
    }

    return $dest
}
