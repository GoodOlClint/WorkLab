BeforeAll {
    Import-Module PSProxmoxVE -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force
}

Describe 'New-WorkLabProviderIso' {
    BeforeEach {
        $script:Ctx = @{ Options = @{ Server = 'pve.lan'; ApiToken = 't'; Node = 'pve1'; IsoStorage = 'local' } }
    }

    It 'fast-fails when IsoStorage is missing' {
        { New-WorkLabProviderIso -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -Url 'https://x/y.iso' -Confirm:$false } |
            Should -Throw -ExpectedMessage '*IsoStorage*'
    }

    It 'downloads by URL when absent and is idempotent when present' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:dl = 0
            Mock Invoke-PveStorageDownload -RemoveParameterType 'Session' { $script:dl++ }
            $script:seen = $false
            Mock Get-PveStorageContent -RemoveParameterType 'Session' {
                if ($script:seen) { [pscustomobject]@{ VolId = 'local:iso/win.iso'; Volume = 'win.iso'; Size = 1 } }
                else { $script:seen = $true; @() }
            }
            $ctx = @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'pve1'; IsoStorage = 'local' } }
            $r = New-WorkLabProviderIso -Context $ctx -Url 'https://example/win.iso' -Confirm:$false
            $r.Existed | Should -BeFalse
            $r.Name | Should -Be 'win.iso'
            $script:dl | Should -Be 1

            # Now it is present -> reconcile, no second download.
            Mock Get-PveStorageContent -RemoveParameterType 'Session' { [pscustomobject]@{ VolId = 'local:iso/win.iso'; Volume = 'win.iso' } }
            $r2 = New-WorkLabProviderIso -Context $ctx -Url 'https://example/win.iso' -Confirm:$false
            $r2.Existed | Should -BeTrue
            $script:dl | Should -Be 1
        }
    }

    It 'uploads a local file by path' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveStorageContent -RemoveParameterType 'Session' { @() }
            $script:up = 0
            Mock Send-PveFile -RemoveParameterType 'Session' { $script:up++ }
            $tmp = Join-Path ([IO.Path]::GetTempPath()) "wl-$([guid]::NewGuid().ToString('N')).iso"
            Set-Content -Path $tmp -Value 'x'
            try {
                $ctx = @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'pve1'; IsoStorage = 'local' } }
                $r = New-WorkLabProviderIso -Context $ctx -Path $tmp -Confirm:$false
                $r.Existed | Should -BeFalse
                $script:up | Should -Be 1
            }
            finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
        }
    }

    It 'rejects a missing local file' {
        { New-WorkLabProviderIso -Context $script:Ctx -Path '/no/such/file.iso' -Confirm:$false } |
            Should -Throw -ExpectedMessage '*not found*'
    }
}

Describe 'Get/Remove-WorkLabProviderIso' {
    It 'normalizes listed ISOs' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveStorageContent -RemoveParameterType 'Session' {
                [pscustomobject]@{ VolId = 'local:iso/a.iso'; Size = 10 }
                [pscustomobject]@{ VolId = 'local:iso/b.iso'; Size = 20 }
            }
            $r = Get-WorkLabProviderIso -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n'; IsoStorage = 'local' } }
            ($r | Measure-Object).Count | Should -Be 2
            $r[0].Name | Should -Be 'a.iso'
            $r[0].Provider | Should -Be 'Proxmox'
        }
    }

    It 'removes when present and no-ops when absent' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:rm = 0
            Mock Remove-PveStorageContent -RemoveParameterType 'Session' { $script:rm++ }
            Mock Get-PveStorageContent -RemoveParameterType 'Session' { [pscustomobject]@{ VolId = 'local:iso/win.iso'; Volume = 'win.iso' } }
            $ctx = @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n'; IsoStorage = 'local' } }
            (Remove-WorkLabProviderIso -Context $ctx -Name win.iso -Confirm:$false).Removed | Should -BeTrue
            $script:rm | Should -Be 1

            Mock Get-PveStorageContent -RemoveParameterType 'Session' { @() }
            (Remove-WorkLabProviderIso -Context $ctx -Name gone.iso -Confirm:$false).Removed | Should -BeFalse
            $script:rm | Should -Be 1
        }
    }
}
