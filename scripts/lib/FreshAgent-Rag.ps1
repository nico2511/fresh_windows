#Requires -Version 5.1
<#
  RAG leger : guides Fresh Windows + recherche mots-cles / embeddings Ollama optionnels.
#>

function Get-FreshAgentRagIndexPath {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'rag\index.json'
}

function Get-FreshAgentRagGuidesDir {
    param([string]$FreshAppData = $(Get-FreshAgentAppDataRoot))
    return Join-Path $FreshAppData 'guides'
}

function Get-FreshAgentRagGuideUrls {
    param([string]$RepoRef)
    $raw = Get-FreshAgentRepoRawRoot -RepoRef $RepoRef
    $names = @('amd-adrenalin.md', 'chipset.md', 'shutup10.md', 'nvidia-nvcleanstall.md')
    $list = @()
    foreach ($n in $names) {
        $list += @{ name = $n; url = "$raw/guides/$n" }
    }
    return $list
}

function Sync-FreshAgentRagGuides {
    param(
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $dir = Get-FreshAgentRagGuidesDir -FreshAppData $FreshAppData
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($g in (Get-FreshAgentRagGuideUrls -RepoRef $RepoRef)) {
        $dest = Join-Path $dir $g.name
        try {
            Invoke-WebRequest -Uri $g.url -OutFile $dest -UseBasicParsing
        }
        catch { }
    }
}

function Split-FreshAgentTextChunks {
    param(
        [string]$Text,
        [int]$MaxLen = 900
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $paras = $Text -split "(\r?\n){2,}"
    $chunks = [System.Collections.ArrayList]@()
    $buf = ''
    foreach ($p in $paras) {
        $piece = $p.Trim()
        if ([string]::IsNullOrWhiteSpace($piece)) { continue }
        if (($buf.Length + $piece.Length + 2) -gt $MaxLen) {
            if ($buf) { [void]$chunks.Add($buf.Trim()) }
            if ($piece.Length -gt $MaxLen) {
                for ($i = 0; $i -lt $piece.Length; $i += $MaxLen) {
                    $end = [Math]::Min($MaxLen, $piece.Length - $i)
                    [void]$chunks.Add($piece.Substring($i, $end).Trim())
                }
                $buf = ''
            }
            else { $buf = $piece }
        }
        else {
            if ($buf) { $buf += "`n`n" }
            $buf += $piece
        }
    }
    if ($buf) { [void]$chunks.Add($buf.Trim()) }
    return @($chunks)
}

function Build-FreshAgentRagIndex {
    param(
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }),
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    Sync-FreshAgentRagGuides -RepoRef $RepoRef -FreshAppData $FreshAppData | Out-Null
    $dir = Get-FreshAgentRagGuidesDir -FreshAppData $FreshAppData
    $docs = [System.Collections.ArrayList]@()
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.md' -ErrorAction SilentlyContinue)) {
        try {
            $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            $i = 0
            foreach ($chunk in (Split-FreshAgentTextChunks -Text $text)) {
                [void]$docs.Add([ordered]@{
                        id      = ('{0}:{1}' -f $file.Name, $i)
                        source  = $file.Name
                        content = $chunk
                    })
                $i++
            }
        }
        catch { }
    }
    $index = [ordered]@{
        schemaVersion = 1
        generatedAt   = (Get-Date).ToString('o')
        repoRef       = $RepoRef
        chunks        = @($docs)
    }
    $path = Get-FreshAgentRagIndexPath -FreshAppData $FreshAppData
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    ($index | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
    return $index
}

function Get-FreshAgentRagIndex {
    param(
        [switch]$RebuildIfMissing,
        [string]$RepoRef,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $path = Get-FreshAgentRagIndexPath -FreshAppData $FreshAppData
    if (-not (Test-Path -LiteralPath $path)) {
        if ($RebuildIfMissing) {
            return Build-FreshAgentRagIndex -RepoRef $RepoRef -FreshAppData $FreshAppData
        }
        return $null
    }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch { return $null }
}

function Search-FreshAgentRagChunks {
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        [int]$TopK = 4,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )
    $index = Get-FreshAgentRagIndex -RebuildIfMissing -RepoRef $RepoRef -FreshAppData $FreshAppData
    if (-not $index -or -not $index.chunks) { return @() }

    $terms = @($Query.ToLowerInvariant() -split '\W+' | Where-Object { $_.Length -gt 2 })
    if ($terms.Count -eq 0) { $terms = @($Query.ToLowerInvariant()) }

    $scored = @()
    foreach ($c in @($index.chunks)) {
        $body = ([string]$c.content).ToLowerInvariant()
        $score = 0
        foreach ($t in $terms) {
            if ($body.Contains($t)) { $score++ }
        }
        if ($score -gt 0) {
            $scored += [pscustomobject]@{ Score = $score; Chunk = $c }
        }
    }
    return @($scored | Sort-Object -Property Score -Descending | Select-Object -First $TopK | ForEach-Object { $_.Chunk })
}

function Get-FreshAgentRagContextText {
    param(
        [string]$UserPrompt,
        $AiConfig,
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot),
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' })
    )
    if (-not $AiConfig -or -not $AiConfig.rag -or -not $AiConfig.rag.enabled) {
        return ''
    }
    $topK = 4
    if ($null -ne $AiConfig.rag.topK) { $topK = [int]$AiConfig.rag.topK }

    $hits = Search-FreshAgentRagChunks -Query $UserPrompt -TopK $topK -FreshAppData $FreshAppData -RepoRef $RepoRef
    if ($hits.Count -eq 0) { return '' }

    $parts = @()
    foreach ($h in $hits) {
        $parts += ("[{0}] {1}" -f $h.source, $h.content)
    }
    return "Extraits guides Fresh Windows:`n" + ($parts -join "`n---`n")
}

function Invoke-SkillRefreshRagIndex {
    param(
        [string]$RepoRef = $(if ($env:FRESH_WIN_REF) { $env:FRESH_WIN_REF.Trim() } else { 'main' }),
        [string]$FreshAppData = $(Get-FreshAgentAppDataRoot)
    )
    $idx = Build-FreshAgentRagIndex -RepoRef $RepoRef -FreshAppData $FreshAppData
    $n = @($idx.chunks).Count
    return @{ ok = $true; message = "Index RAG MAJ ($n chunks)." }
}
