#Requires -Version 5.1
<#
  Telecharge un script GitHub dans %LOCALAPPDATA%\FreshWindows si ref change ou fichier absent.
  Retourne le chemin local (sans dot-source).
#>
function ConvertTo-Utf8BomFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return
    }
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    [IO.File]::WriteAllText($Path, $text, $utf8Bom)
}

function Get-FreshWindowsCachedScriptPath {
    param(
        [Parameter(Mandatory)][string]$CacheFileName,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$RepoRawRoot,
        [Parameter(Mandatory)][string]$RepoRef,
        [Parameter(Mandatory)][string]$FreshAppData,
        [string]$LibEpoch = '',
        [switch]$ForceRefresh
    )

    New-Item -ItemType Directory -Path $FreshAppData -Force | Out-Null
    $dest = Join-Path $FreshAppData $CacheFileName
    $meta = Join-Path $FreshAppData "$CacheFileName.ref"
    $url  = "$RepoRawRoot/$RemotePath"

    if ([string]::IsNullOrWhiteSpace($LibEpoch) -and $script:FreshWindowsLibEpoch) {
        $LibEpoch = [string]$script:FreshWindowsLibEpoch
    }
    $cacheToken = if ($LibEpoch) { "$RepoRef|$LibEpoch" } else { $RepoRef }

    $needFetch = $ForceRefresh -or -not (Test-Path -LiteralPath $dest)
    if (-not $needFetch -and (Test-Path -LiteralPath $meta)) {
        try {
            $savedRef = (Get-Content -LiteralPath $meta -Raw -Encoding UTF8).Trim()
            if ($savedRef -ne $cacheToken) { $needFetch = $true }
        }
        catch { $needFetch = $true }
    }
    elseif (-not (Test-Path -LiteralPath $meta)) {
        $needFetch = $true
    }

    if ($needFetch) {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
        Set-Content -LiteralPath $meta -Value $cacheToken -Encoding UTF8 -NoNewline
    }

    ConvertTo-Utf8BomFile -Path $dest
    return $dest
}
