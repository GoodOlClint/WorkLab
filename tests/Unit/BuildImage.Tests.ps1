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
                # No guest-agent install command when -GuestAgentMsiPath omitted
                $xml | Should -Not -BeLike '*msiexec*qemu-ga*'
                # Disk must be wiped + partitioned + targeted, or Setup loops
                # with no bootable disk. Default firmware is UEFI: GPT layout
                # with EFI + MSR + Windows, install to partition 3.
                # Must be well-formed XML WITH the wcm namespace declared, or
                # Setup rejects the whole file ("'wcm' is an undeclared prefix")
                # and resets at launch. Casting to [xml] fails if wcm/xsi aren't
                # declared, since every element uses wcm:action.
                $xml | Should -BeLike '*xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"*'
                { [xml]$xml } | Should -Not -Throw
                $xml | Should -BeLike '*<DiskConfiguration>*'
                $xml | Should -BeLike '*<WillWipeDisk>true</WillWipeDisk>*'
                $xml | Should -BeLike '*<Type>EFI</Type>*'
                $xml | Should -BeLike '*<Type>MSR</Type>*'
                $xml | Should -BeLike '*<InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>*'
                # UEFI has no active-partition concept.
                $xml | Should -Not -BeLike '*<Active>true</Active>*'
            }
            finally { Remove-Item $out -ErrorAction SilentlyContinue }
        }
    }

    It 'embeds a ProductKey block when -ProductKey is supplied (and omits it otherwise)' {
        InModuleScope WorkLab {
            $ss = ConvertTo-SecureString 'P@ss' -AsPlainText -Force
            $out = Join-Path ([IO.Path]::GetTempPath()) "wl-aupk-$([guid]::NewGuid().ToString('N')).xml"
            try {
                New-WorkLabAutounattend -Edition 1 -AdminPassword $ss -ProductKey 'TVRH6-WHNXV-R9WG3-9XRFY-MY832' -OutFile $out | Out-Null
                $xml = Get-Content -LiteralPath $out -Raw
                { [xml]$xml } | Should -Not -Throw
                $xml | Should -BeLike '*<ProductKey><Key>TVRH6-WHNXV-R9WG3-9XRFY-MY832</Key>*'

                New-WorkLabAutounattend -Edition 1 -AdminPassword $ss -OutFile $out | Out-Null
                (Get-Content -LiteralPath $out -Raw) | Should -Not -BeLike '*<ProductKey>*'
            }
            finally { Remove-Item $out -ErrorAction SilentlyContinue }
        }
    }

    It 'emits a legacy-BIOS MBR layout when -Firmware Bios' {
        InModuleScope WorkLab {
            $ss = ConvertTo-SecureString 'P@ss' -AsPlainText -Force
            $out = Join-Path ([IO.Path]::GetTempPath()) "wl-aubios-$([guid]::NewGuid().ToString('N')).xml"
            try {
                New-WorkLabAutounattend -Edition 1 -AdminPassword $ss -Firmware Bios -OutFile $out | Out-Null
                $xml = Get-Content -LiteralPath $out -Raw
                # MBR: single active primary, install to partition 1, no EFI/MSR.
                $xml | Should -BeLike '*<Active>true</Active>*'
                $xml | Should -BeLike '*<InstallTo><DiskID>0</DiskID><PartitionID>1</PartitionID></InstallTo>*'
                $xml | Should -Not -BeLike '*<Type>EFI</Type>*'
                $xml | Should -Not -BeLike '*<Type>MSR</Type>*'
            }
            finally { Remove-Item $out -ErrorAction SilentlyContinue }
        }
    }

    It 'injects an agent-install SynchronousCommand BEFORE sysprep when -GuestAgentMsiPath is set' {
        InModuleScope WorkLab {
            $ss = ConvertTo-SecureString 'P@ss' -AsPlainText -Force
            $out = Join-Path ([IO.Path]::GetTempPath()) "wl-au2-$([guid]::NewGuid().ToString('N')).xml"
            try {
                New-WorkLabAutounattend -Edition 1 -AdminPassword $ss `
                    -GuestAgentMsiPath 'C:\Windows\Setup\Files\qemu-ga.msi' -OutFile $out | Out-Null
                $xml = Get-Content -LiteralPath $out -Raw
                $xml | Should -BeLike '*msiexec /i "C:\Windows\Setup\Files\qemu-ga.msi" /qn /norestart*'
                $xml | Should -BeLike '*<Order>1</Order>*msiexec*'
                $xml | Should -BeLike '*<Order>2</Order>*Sysprep.exe /generalize*'
                # Agent install precedes sysprep textually as well.
                $msiIdx = $xml.IndexOf('msiexec')
                $sysIdx = $xml.IndexOf('Sysprep.exe')
                $msiIdx | Should -BeLessThan $sysIdx
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
        # Platform-native fake root: Join-Path on Windows normalizes / to \,
        # so the assertion must use the native separator. Pass into the
        # InModuleScope so the inner assertion sees the same value.
        $sep = [IO.Path]::DirectorySeparatorChar
        $fakeRoot = "${sep}fake${sep}pf86"
        ${env:ProgramFiles(x86)} = $fakeRoot
        InModuleScope WorkLab -Parameters @{ FakeRoot = $fakeRoot } {
            param($FakeRoot)
            Mock Get-Command -ParameterFilter { $Name -eq 'oscdimg.exe' } { }
            Mock Test-Path { $true } -ParameterFilter { "$LiteralPath" -like '*Oscdimg*oscdimg.exe' }
            $result = Resolve-WorkLabOscdimg
            $result | Should -BeLike '*Oscdimg*oscdimg.exe'
            $result | Should -BeLike "$FakeRoot*"
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

    It 'with -VirtioWinIso: injects virtio drivers, stages qemu-ga MSI, and threads GuestAgentMsiPath through' {
        $virtioSrc = Join-Path ([IO.Path]::GetTempPath()) "wl-virtio-$([guid]::NewGuid().ToString('N')).iso"
        Set-Content -LiteralPath $virtioSrc -Value 'fake-virtio' -NoNewline
        try {
            InModuleScope WorkLab -Parameters @{ Src = $script:Src; Cred = $script:Cred; VSrc = $virtioSrc } {
                param([string]$Src, [pscredential]$Cred, [string]$VSrc)

                Mock Assert-WorkLabDismAvailable { }
                Mock Resolve-WorkLabImageAdminCredential { $Cred }
                Mock Expand-WorkLabIsoSource { param($SourceIso, $WorkDir) $WorkDir }
                Mock Mount-WorkLabWim { param($WimPath, $Edition, $MountDir) $MountDir }
                $script:wimAdds = 0
                Mock Add-WorkLabWimContent { $script:wimAdds++ }
                Mock Dismount-WorkLabWim { }
                # boot.wim has two images (1=WinPE, 2=Setup); virtio drivers go
                # into each so Setup can see the virtio0 disk.
                $script:bootIndexCalls = 0
                Mock Get-WorkLabWimIndex { $script:bootIndexCalls++; @(1, 2) }
                Mock New-WorkLabBootableIso { param($WorkDir, $IsoPath) Set-Content -LiteralPath $IsoPath -Value 'iso'; $IsoPath }

                $script:virtioMounts = 0
                $script:virtioDismounts = 0
                Mock Mount-WorkLabVirtioWin {
                    $script:virtioMounts++
                    [pscustomobject]@{
                        Volume = '/v'; DriverPath = '/v/amd64'
                        AgentMsiPath = '/v/guest-agent/qemu-ga-x86_64.msi'
                    }
                }
                Mock Dismount-WorkLabVirtioWin { $script:virtioDismounts++ }

                $script:msiCopies = 0
                Mock Copy-Item -ParameterFilter { "$LiteralPath" -like '*qemu-ga*.msi' } { $script:msiCopies++ }

                # Capture the agent path Autounattend was called with. Pester
                # mocks expose bound params as auto-vars; $PSBoundParameters in
                # the mock body is the *mock scriptblock's* PSBP, not the
                # mocked cmdlet's.
                $script:auaGuestAgent = $null
                Mock New-WorkLabAutounattend { $script:auaGuestAgent = $GuestAgentMsiPath; $OutFile }

                $r = Build-WorkLabImage -Name wsv -SourceIso $Src -VirtioWinIso $VSrc -Confirm:$false
                $r.Existed | Should -BeFalse
                $r.Manifest.virtioSha256 | Should -Match '^[0-9a-f]{64}$'
                $r.Manifest.guestAgentPath | Should -Be 'C:\Windows\Setup\Files\qemu-ga.msi'

                $script:virtioMounts | Should -Be 1
                $script:virtioDismounts | Should -Be 1
                $script:msiCopies | Should -Be 1
                # Add-WorkLabWimContent calls: install.wim gets virtio + user
                # drivers (2), then boot.wim gets virtio drivers per image (2:
                # WinPE + Setup) = 4 total. boot.wim indices were enumerated once.
                $script:wimAdds | Should -Be 4
                $script:bootIndexCalls | Should -Be 1
                # Autounattend received the in-guest agent path.
                $script:auaGuestAgent | Should -Be 'C:\Windows\Setup\Files\qemu-ga.msi'
            }
        }
        finally { Remove-Item -LiteralPath $virtioSrc -ErrorAction SilentlyContinue }
    }

    It 'throws when the source ISO is missing (after the Windows gate)' {
        InModuleScope WorkLab {
            Mock Assert-WorkLabDismAvailable { }
            { Build-WorkLabImage -Name ws -SourceIso '/no/such.iso' -Confirm:$false } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }
}
