BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab/WorkLab.psd1') -Force
    $script:Cache = Join-Path ([System.IO.Path]::GetTempPath()) "wl-bimg-$([guid]::NewGuid().ToString('N'))"
    $env:WORKLAB_CACHE_PATH = $script:Cache
    $script:Src = Join-Path ([System.IO.Path]::GetTempPath()) "wl-src-$([guid]::NewGuid().ToString('N')).iso"
    Set-Content -LiteralPath $script:Src -Value 'fake-iso-bytes' -NoNewline
    $script:Cred = [pscredential]::new('Administrator', (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force))
}

AfterAll {
    Remove-Item env:WORKLAB_CACHE_PATH -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $script:Cache -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:Src -ErrorAction SilentlyContinue
}

Describe 'Build-WorkLabImage Windows gate' {
    It 'fast-fails on a non-Windows host' -Skip:($IsWindows) {
        { Build-WorkLabImage -Name img -SourceIso $script:Src -Confirm:$false } |
            Should -Throw -ExpectedMessage '*Windows*'
    }
}

Describe 'New-WorkLabAutounattend' {
    It 'embeds the spec-correct base64 password and locale' {
        InModuleScope WorkLab {
            $ss = ConvertTo-SecureString 'P@ss' -AsPlainText -Force
            $out = Join-Path ([IO.Path]::GetTempPath()) "wl-au-$([guid]::NewGuid().ToString('N')).xml"
            try {
                New-WorkLabAutounattend -Edition 2 -AdminPassword $ss -Locale 'en-GB' -OutFile $out | Out-Null
                $xml = Get-Content -LiteralPath $out -Raw
                $expected = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes('P@ss' + 'AdministratorPassword'))
                $xml | Should -BeLike "*<Value>$expected</Value>*"
                $xml | Should -BeLike '*<PlainText>false</PlainText>*'
                $xml | Should -BeLike '*<UILanguage>en-GB</UILanguage>*'
                $xml | Should -BeLike '*/IMAGE/INDEX*'
                $xml | Should -BeLike '*Sysprep.exe /generalize /oobe /shutdown*'
                $xml | Should -BeLike '*<AutoLogon>*'
            }
            finally { Remove-Item $out -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Resolve-WorkLabOscdimg' {
    # Helper: set/restore ${env:ProgramFiles(x86)} (absent on non-Windows)
    BeforeAll { $script:Pf86Original = ${env:ProgramFiles(x86)} }
    AfterEach {
        if ($null -eq $script:Pf86Original) {
            Remove-Item -LiteralPath 'env:ProgramFiles(x86)' -ErrorAction SilentlyContinue
        }
        else {
            ${env:ProgramFiles(x86)} = $script:Pf86Original
        }
    }

    It 'returns the PATH location when oscdimg is on PATH' {
        InModuleScope WorkLab {
            Mock Get-Command -ParameterFilter { $Name -eq 'oscdimg.exe' } {
                [pscustomobject]@{ Source = '/somewhere/oscdimg.exe' }
            }
            (Resolve-WorkLabOscdimg) | Should -Be '/somewhere/oscdimg.exe'
        }
    }

    It 'falls back to the ADK default location when not on PATH' {
        ${env:ProgramFiles(x86)} = '/fake/pf86'
        InModuleScope WorkLab {
            Mock Get-Command -ParameterFilter { $Name -eq 'oscdimg.exe' } { }
            Mock Test-Path { $true } -ParameterFilter { "$LiteralPath" -like '*Oscdimg*oscdimg.exe' }
            $result = Resolve-WorkLabOscdimg
            $result | Should -BeLike '*Oscdimg*oscdimg.exe'
            $result | Should -BeLike '/fake/pf86*'
        }
    }

    It 'throws a teaching error when neither location resolves' {
        Remove-Item -LiteralPath 'env:ProgramFiles(x86)' -ErrorAction SilentlyContinue
        InModuleScope WorkLab {
            Mock Get-Command -ParameterFilter { $Name -eq 'oscdimg.exe' } { }
            { Resolve-WorkLabOscdimg } | Should -Throw -ExpectedMessage '*ADK*'
        }
    }
}

Describe 'Resolve-WorkLabImageAdminCredential' {
    It 'prefers an explicit credential' {
        InModuleScope WorkLab {
            $c = [pscredential]::new('a', (ConvertTo-SecureString 'b' -AsPlainText -Force))
            (Resolve-WorkLabImageAdminCredential -Name img -AdminCredential $c).UserName | Should -Be 'a'
        }
    }
    It 'falls back to the image secret and rejects non-credential secrets' {
        InModuleScope WorkLab {
            Mock Get-WorkLabSecret { [pscredential]::new('svc', (ConvertTo-SecureString 'x' -AsPlainText -Force)) }
            (Resolve-WorkLabImageAdminCredential -Name img).UserName | Should -Be 'svc'

            Mock Get-WorkLabSecret { 'just-a-string' }
            { Resolve-WorkLabImageAdminCredential -Name img } | Should -Throw -ExpectedMessage '*not a PSCredential*'
        }
    }
}

Describe 'Build-WorkLabImage pipeline (seams mocked)' {
    BeforeEach {
        Remove-Item -Recurse -Force $script:Cache -ErrorAction SilentlyContinue
    }

    It 'patches, writes a manifest, and is idempotent' {
        InModuleScope WorkLab -Parameters @{ Src = $script:Src; Cred = $script:Cred } {
            param([string]$Src, [pscredential]$Cred)
            Mock Assert-WorkLabDismAvailable { }
            Mock Resolve-WorkLabImageAdminCredential { $Cred }
            Mock Expand-WorkLabIsoSource { param($SourceIso, $WorkDir) $WorkDir }
            Mock Mount-WorkLabWim { param($WimPath, $Edition, $MountDir) $MountDir }
            Mock Add-WorkLabWimContent { }
            $script:saved = 0
            Mock Dismount-WorkLabWim { if (-not $Discard) { $script:saved++ } }
            $script:built = 0
            Mock New-WorkLabBootableIso { param($WorkDir, $IsoPath) $script:built++; Set-Content -LiteralPath $IsoPath -Value 'iso'; $IsoPath }

            $r = Build-WorkLabImage -Name ws -SourceIso $Src -Edition 2 -Confirm:$false
            $r.Existed | Should -BeFalse
            $r.Manifest.edition | Should -Be '2'
            $r.Manifest.sourceSha256 | Should -Match '^[0-9a-f]{64}$'
            Test-Path $r.IsoPath | Should -BeTrue
            $script:saved | Should -Be 1
            $script:built | Should -Be 1

            # Idempotent: same inputs -> reconcile, no rebuild
            $r2 = Build-WorkLabImage -Name ws -SourceIso $Src -Edition 2 -Confirm:$false
            $r2.Existed | Should -BeTrue
            $script:built | Should -Be 1

            # -Force rebuilds
            Build-WorkLabImage -Name ws -SourceIso $Src -Edition 2 -Force -Confirm:$false | Out-Null
            $script:built | Should -Be 2
        }
    }

    It 'discards the WIM mount and rethrows on injection failure' {
        InModuleScope WorkLab -Parameters @{ Src = $script:Src; Cred = $script:Cred } {
            param([string]$Src, [pscredential]$Cred)
            Mock Assert-WorkLabDismAvailable { }
            Mock Resolve-WorkLabImageAdminCredential { $Cred }
            Mock Expand-WorkLabIsoSource { param($SourceIso, $WorkDir) $WorkDir }
            Mock Mount-WorkLabWim { param($WimPath, $Edition, $MountDir) $MountDir }
            Mock Add-WorkLabWimContent { throw 'driver injection blew up' }
            $script:discarded = 0
            Mock Dismount-WorkLabWim { if ($Discard) { $script:discarded++ } }
            Mock New-WorkLabBootableIso { }

            { Build-WorkLabImage -Name ws -SourceIso $Src -Confirm:$false } |
                Should -Throw -ExpectedMessage '*driver injection blew up*'
            $script:discarded | Should -Be 1
        }
    }

    It 'throws when the source ISO is missing (after the Windows gate)' {
        InModuleScope WorkLab {
            Mock Assert-WorkLabDismAvailable { }
            { Build-WorkLabImage -Name ws -SourceIso '/no/such.iso' -Confirm:$false } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }
}
