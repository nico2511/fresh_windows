#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

Describe 'Resolve-FreshAgentModelsDir' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        . (Join-Path $root 'scripts\lib\FreshAgent-SttSettings.ps1')
        if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = Join-Path $env:HOME '.local/share' }
        $baseTemp = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { '/tmp' }
        $script:Tmp = Join-Path $baseTemp ('FreshAgent-ModelsDir-' + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null
    }

    AfterAll {
        if ($script:Tmp -and (Test-Path -LiteralPath $script:Tmp)) {
            Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path Env:FRESH_MODELS_DIR) { Remove-Item Env:FRESH_MODELS_DIR }
    }

    BeforeEach {
        Get-ChildItem -LiteralPath $script:Tmp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path Env:FRESH_MODELS_DIR) { Remove-Item Env:FRESH_MODELS_DIR }
        $flag = Join-Path $script:Tmp 'fa-models-legacy-notified.txt'
        if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag -Force }
    }

    It 'utilise freshModelsDir depuis agent-ai.user.json' {
        $custom = Join-Path $script:Tmp 'user-models'
        New-Item -ItemType Directory -Path $custom -Force | Out-Null
        $userAi = Join-Path $script:Tmp 'agent-ai.user.json'
        @{ freshModelsDir = $custom } | ConvertTo-Json | Set-Content -LiteralPath $userAi -Encoding UTF8
        Resolve-FreshAgentModelsDir -FreshAppData $script:Tmp | Should -Be $custom
    }

    It 'utilise FRESH_MODELS_DIR quand aucune config user' {
        $envDir = Join-Path $script:Tmp 'from-env'
        New-Item -ItemType Directory -Path $envDir -Force | Out-Null
        $env:FRESH_MODELS_DIR = $envDir
        Resolve-FreshAgentModelsDir -FreshAppData $script:Tmp | Should -Be $envDir
    }

    It 'defaut LOCALAPPDATA FreshWindows models sans legacy Windows' {
        $local = $env:LOCALAPPDATA
        if ([string]::IsNullOrWhiteSpace($local) -and $env:USERPROFILE) {
            $local = Join-Path $env:USERPROFILE 'AppData\Local'
        }
        $expected = Join-Path $local 'FreshWindows\models'
        $noLegacy = Join-Path $TestDrive 'FreshAgent-NoLegacyModelsDir'
        Resolve-FreshAgentModelsDir -FreshAppData $script:Tmp -LegacyModelsPath $noLegacy | Should -Be $expected
    }

    It 'retrocompat chemin legacy si present et sans reglage (isole)' {
        $legacy = Join-Path $script:Tmp 'legacy-cyberscribe-models'
        New-Item -ItemType Directory -Path $legacy -Force | Out-Null
        $logged = New-Object System.Collections.ArrayList
        $null = Resolve-FreshAgentModelsDir -FreshAppData $script:Tmp -LegacyModelsPath $legacy -OnLegacyPath {
            param($m)
            [void]$logged.Add($m)
        }
        Resolve-FreshAgentModelsDir -FreshAppData $script:Tmp -LegacyModelsPath $legacy | Should -Be $legacy
        $logged.Count | Should -BeGreaterOrEqual 1
        $flag = Join-Path $script:Tmp 'fa-models-legacy-notified.txt'
        Test-Path -LiteralPath $flag | Should -Be $true
        $logged2 = New-Object System.Collections.ArrayList
        $null = Resolve-FreshAgentModelsDir -FreshAppData $script:Tmp -LegacyModelsPath $legacy -OnLegacyPath {
            param($m)
            [void]$logged2.Add($m)
        }
        $logged2.Count | Should -Be 0
    }
}

Describe 'Format-FreshAgentTranscriptForLog' {
    BeforeAll {
        $root = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath (Join-Path $root 'scripts'))) {
            $here = $PSScriptRoot
            if ([string]::IsNullOrWhiteSpace($here)) { $here = Split-Path -Parent $PSCommandPath }
            $root = Split-Path -Parent $here
        }
        . (Join-Path $root 'scripts\lib\FreshAgent-Log.ps1')
        $script:Tmp = Join-Path $env:TEMP ('FreshAgent-LogMask-' + [Guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null
    }

    AfterAll {
        if ($script:Tmp -and (Test-Path -LiteralPath $script:Tmp)) {
            Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    BeforeEach {
        Get-ChildItem -LiteralPath $script:Tmp -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    It 'masque par defaut (len + sha256)' {
        $text = 'lance Steam'
        $line = Format-FreshAgentTranscriptForLog -Text $text -FreshAppData $script:Tmp
        $line | Should -Match '^len=\d+ sha256=[0-9a-f]{8}$'
        $line | Should -Not -Be $text
        $fp = Get-FreshAgentTranscriptSha256Prefix8 -Text $text
        $line | Should -Be ("len={0} sha256={1}" -f $text.Length, $fp)
    }

    It 'texte en clair si logTranscripts true' {
        $watch = Join-Path $script:Tmp 'watch-agent-user.json'
        @{ logTranscripts = $true } | ConvertTo-Json | Set-Content -LiteralPath $watch -Encoding UTF8
        $text = 'ouvre Chrome'
        Format-FreshAgentTranscriptForLog -Text $text -FreshAppData $script:Tmp | Should -Be $text
    }
}
