#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $root 'scripts\lib\FreshAgent-Config.ps1')
. (Join-Path $root 'scripts\lib\FreshAgent-Rag.ps1')

Describe 'FreshAgent RAG' {
    It 'Index and search guides' {
        $tmp = Join-Path $env:TEMP ('FreshAgent-Rag-{0}' -f [guid]::NewGuid().ToString('N'))
        $guides = Join-Path $tmp 'guides'
        New-Item -ItemType Directory -Path $guides -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $guides 'shutup10.md') -Value 'ShutUp10 desactive la telemetrie Windows.' -Encoding UTF8
        $idx = Build-FreshAgentRagIndex -RepoRef 'main' -FreshAppData $tmp
        @($idx.chunks).Count | Should -BeGreaterThan 0
        $hits = Search-FreshAgentRagChunks -Query 'telemetrie ShutUp10' -FreshAppData $tmp -RepoRef 'main'
        $hits.Count | Should -BeGreaterThan 0
        Remove-Item -LiteralPath $tmp -Recurse -Force
    }
}
