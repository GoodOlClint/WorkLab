BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
    $script:Cache = Join-Path ([System.IO.Path]::GetTempPath()) "wl-imgcache-$([guid]::NewGuid().ToString('N'))"
    $env:WORKLAB_CACHE_PATH = $script:Cache
}

AfterAll {
    Remove-Item env:WORKLAB_CACHE_PATH -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $script:Cache -ErrorAction SilentlyContinue
}

Describe 'Image cache private helpers' {
    BeforeEach { Remove-Item -Recurse -Force $script:Cache -ErrorAction SilentlyContinue }

    It 'Get-WorkLabImageRoot honors WORKLAB_CACHE_PATH' {
        InModuleScope WorkLab {
            (Get-WorkLabImageRoot) | Should -Be (Join-Path $env:WORKLAB_CACHE_PATH 'images')
        }
    }
    It 'manifest write/read round-trips' {
        InModuleScope WorkLab {
            $m = [pscustomobject]@{ schema = 'worklab.image/v1'; name = 'img1'; edition = 3 }
            $p = Write-WorkLabImageManifest -Name img1 -Manifest $m
            Test-Path $p | Should -BeTrue
            (Read-WorkLabImageManifest -Name img1).edition | Should -Be 3
            Read-WorkLabImageManifest -Name nope | Should -BeNullOrEmpty
        }
    }
    It 'checksum is stable and null for missing' {
        InModuleScope WorkLab {
            $f = Join-Path ([IO.Path]::GetTempPath()) "wl-ck-$([guid]::NewGuid().ToString('N'))"
            Set-Content -LiteralPath $f -Value 'worklab' -NoNewline
            try {
                $h1 = Get-WorkLabFileChecksum -Path $f
                $h2 = Get-WorkLabFileChecksum -Path $f
                $h1 | Should -Be $h2
                $h1 | Should -Match '^[0-9a-f]{64}$'
                Get-WorkLabFileChecksum -Path "$f.missing" | Should -BeNullOrEmpty
            }
            finally { Remove-Item $f -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Get-WorkLabImage' {
    BeforeEach { Remove-Item -Recurse -Force $script:Cache -ErrorAction SilentlyContinue }

    It 'returns nothing when the cache is empty' {
        Get-WorkLabImage | Should -BeNullOrEmpty
    }
    It 'lists images with a manifest and filters by name' {
        $root = Join-Path $script:Cache 'images'
        foreach ($n in 'ws2025-core', 'ws2022-gui') {
            $d = Join-Path $root $n
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            Set-Content -Path (Join-Path $d "$n.image.json") -Value (@{ schema = 'worklab.image/v1'; name = $n; edition = 1 } | ConvertTo-Json)
            Set-Content -Path (Join-Path $d "$n.iso") -Value 'iso-bytes'
        }
        # a folder without a manifest is ignored
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'orphan') | Out-Null

        $all = @(Get-WorkLabImage)
        $all.Count | Should -Be 2
        $all.Name | Should -Not -Contain 'orphan'

        $one = Get-WorkLabImage -Name ws2025-core
        @($one).Count | Should -Be 1
        $one.Name | Should -Be 'ws2025-core'
        $one.SizeBytes | Should -BeGreaterThan 0
        $one.Manifest.edition | Should -Be 1
    }
}

Describe 'Remove-WorkLabImage' {
    BeforeEach { Remove-Item -Recurse -Force $script:Cache -ErrorAction SilentlyContinue }

    It 'no-ops when the image is absent' {
        (Remove-WorkLabImage -Name ghost -Confirm:$false).Removed | Should -BeFalse
    }
    It 'removes the image folder when present' {
        $d = Join-Path $script:Cache 'images/img1'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        Set-Content -Path (Join-Path $d 'img1.image.json') -Value '{}'
        (Remove-WorkLabImage -Name img1 -Confirm:$false).Removed | Should -BeTrue
        Test-Path $d | Should -BeFalse
    }
}
