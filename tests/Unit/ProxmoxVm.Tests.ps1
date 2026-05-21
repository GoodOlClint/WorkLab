BeforeAll {
    Import-Module PSProxmoxVE -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force
}

Describe 'New-WorkLabProviderVm' {
    It 'fast-fails without DiskStorage' {
        { New-WorkLabProviderVm -Context @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01 -Confirm:$false } |
            Should -Throw -ExpectedMessage '*DiskStorage*'
    }

    It 'fast-fails when the per-lab network is absent' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { }            # not existing
            Mock Get-PveSdnVnet -RemoveParameterType 'Session' { }       # no lab network
            $ctx = @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n'; DiskStorage = 'local-lvm' } }
            { New-WorkLabProviderVm -Context $ctx -VmName lab-demo-dc01 -Confirm:$false } |
                Should -Throw -ExpectedMessage '*does not exist*'
        }
    }

    It 'creates when absent and is idempotent when present' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveSdnVnet -RemoveParameterType 'Session' { [pscustomobject]@{ Vnet = 'lXXXXXXX' } }
            $script:created = 0
            Mock New-PveVm -RemoveParameterType 'Session' { $script:created++ }
            $script:vmExists = $false
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($script:vmExists) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped'; Node = 'n' } }
            }
            $ctx = @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n'; DiskStorage = 'local-lvm' } }

            # absent -> create; the post-create resolve must see it
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($script:created -ge 1) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped'; Node = 'n' } }
            }
            $r = New-WorkLabProviderVm -Context $ctx -VmName lab-demo-dc01 -Confirm:$false
            $r.Existed | Should -BeFalse
            $r.Name | Should -Be 'lab-demo-dc01'
            $script:created | Should -Be 1

            # present -> reconcile, no second create
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped'; Node = 'n' } }
            $r2 = New-WorkLabProviderVm -Context $ctx -VmName lab-demo-dc01 -Confirm:$false
            $r2.Existed | Should -BeTrue
            $script:created | Should -Be 1
        }
    }

    It 'normalizes DiskSize ("60G" -> "60") before calling New-PveVm (LVM-storage workaround)' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveSdnVnet -RemoveParameterType 'Session' { [pscustomobject]@{ Vnet = 'lXXXXXXX' } }
            $script:seenDiskSize = $null
            Mock New-PveVm -RemoveParameterType 'Session' { $script:seenDiskSize = $DiskSize }
            $script:made = $false
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($script:made) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
                else { $script:made = $true }
            }
            New-WorkLabProviderVm -Context @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n'; DiskStorage = 'lvm' } } `
                -VmName lab-demo-dc01 -DiskSize '60G' -Confirm:$false | Out-Null
            $script:seenDiskSize | Should -Be '60'
        }
    }

    It 'attaches an ISO (requires IsoStorage) via Set-PveVmConfig with ide2 only (no boot key)' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveSdnVnet -RemoveParameterType 'Session' { [pscustomobject]@{ Vnet = 'lXXXXXXX' } }
            Mock New-PveVm -RemoveParameterType 'Session' { }
            $script:cfg = 0
            $script:cfgKeys = $null
            Mock Set-PveVmConfig -RemoveParameterType 'Session' { $script:cfg++; $script:cfgKeys = @($AdditionalConfig.Keys) }
            $script:made = $false
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($script:made) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
                else { $script:made = $true }
            }
            { New-WorkLabProviderVm -Context @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n'; DiskStorage = 'd' } } -VmName lab-demo-dc01 -IsoName win.iso -Confirm:$false } |
                Should -Throw -ExpectedMessage '*IsoStorage*'
            Mock Get-PveVm -RemoveParameterType 'Session' { if ($script:made) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123 } } else { $script:made = $true } }
            $script:made = $false
            New-WorkLabProviderVm -Context @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n'; DiskStorage = 'd'; IsoStorage = 'local' } } -VmName lab-demo-dc01 -IsoName win.iso -Confirm:$false | Out-Null
            $script:cfg | Should -Be 1
            # Workaround for the PSProxmoxVE Set-PveVmConfig bug: a 'boot' key
            # makes it re-emit the disk devices in the order string as malformed
            # drive params ("<dev>: unable to parse drive options"). We set ide2
            # only and let Proxmox auto-append it to the boot order (CD-last,
            # which is what unattended Windows install wants).
            $script:cfgKeys | Should -Contain 'ide2'
            $script:cfgKeys | Should -Not -Contain 'boot'
        }
    }

    It 'attaches the ISO BEFORE starting (no bootloop on empty disk)' {
        # Regression: when -Start and -IsoName were both passed, New-PveVm was
        # called with Start=$true and the VM powered on before Set-PveVmConfig
        # attached the CD-ROM -> "no available device" bootloop. The CD-ROM
        # must be attached while the VM is still stopped, then started.
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveSdnVnet -RemoveParameterType 'Session' { [pscustomobject]@{ Vnet = 'lXXXXXXX' } }
            $script:order = [System.Collections.Generic.List[string]]::new()
            Mock New-PveVm -RemoveParameterType 'Session' {
                # New-PveVm must NOT receive Start — start is a separate step now.
                if ($PSBoundParameters.ContainsKey('Start')) { $script:order.Add('New-PveVm+Start') }
                else { $script:order.Add('New-PveVm') }
            }
            Mock Set-PveVmConfig -RemoveParameterType 'Session' { $script:order.Add('Set-PveVmConfig') }
            Mock Start-PveVm -RemoveParameterType 'Session' { $script:order.Add('Start-PveVm') }
            $script:made = $false
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($script:made) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'running' } }
                else { $script:made = $true }
            }
            New-WorkLabProviderVm -Context @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n'; DiskStorage = 'd'; IsoStorage = 'local' } } `
                -VmName lab-demo-dc01 -IsoName win.iso -Start -Confirm:$false | Out-Null

            $script:order | Should -Be @('New-PveVm', 'Set-PveVmConfig', 'Start-PveVm')
        }
    }
}

Describe 'Get-WorkLabProviderVm' {
    It 'single mode returns the VM, list mode filters by slug prefix' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' {
                if ($VmId) { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = $VmId; Status = 'running'; Node = 'n' } }
                else {
                    [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'running' }
                    [pscustomobject]@{ Name = 'lab-demo-mem01'; VmId = 9200; Status = 'stopped' }
                    [pscustomobject]@{ Name = 'lab-other-dc01'; VmId = 9300; Status = 'stopped' }
                }
            }
            $one = Get-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01
            $one.Provider | Should -Be 'Proxmox'
            $one.Name | Should -Be 'lab-demo-dc01'

            $list = Get-WorkLabProviderVm -Context @{ Slug = 'demo'; Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } }
            ($list | Measure-Object).Count | Should -Be 2
            $list.Name | Should -Not -Contain 'lab-other-dc01'
        }
    }
}

Describe 'Start/Stop/Remove-WorkLabProviderVm idempotency' {
    It 'Start: throws when absent, no-op when running, starts when stopped' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:started = 0
            Mock Start-PveVm -RemoveParameterType 'Session' { $script:started++ }

            Mock Get-PveVm -RemoveParameterType 'Session' { }
            { Start-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01 -Confirm:$false } |
                Should -Throw -ExpectedMessage '*not found*'

            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'running' } }
            (Start-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01 -Confirm:$false).Changed | Should -BeFalse

            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
            (Start-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01 -Confirm:$false).Changed | Should -BeTrue
            $script:started | Should -Be 1
        }
    }

    It 'Remove: no-op when absent, removes when present' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            $script:removed = 0
            Mock Remove-PveVm -RemoveParameterType 'Session' { $script:removed++ }

            Mock Get-PveVm -RemoveParameterType 'Session' { }
            (Remove-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01 -Confirm:$false).Removed | Should -BeFalse
            $script:removed | Should -Be 0

            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
            (Remove-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01 -Confirm:$false).Removed | Should -BeTrue
            $script:removed | Should -Be 1
        }
    }
}
