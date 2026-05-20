BeforeAll {
    Import-Module PSProxmoxVE -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force
}

Describe 'Get-WorkLabProxmoxVmIdentity' {
    It 'is deterministic and stays within the VMID pool' {
        InModuleScope WorkLab.Proxmox {
            $a = Get-WorkLabProxmoxVmIdentity -Name 'lab-twoforest-dc01'
            $b = Get-WorkLabProxmoxVmIdentity -Name 'lab-twoforest-dc01'
            $a.VmId | Should -Be $b.VmId
            $a.Name | Should -Be 'lab-twoforest-dc01'
            $a.VmId | Should -BeGreaterOrEqual 9000
            $a.VmId | Should -BeLessOrEqual 9999
        }
    }
    It 'honors a custom pool' {
        InModuleScope WorkLab.Proxmox {
            $id = Get-WorkLabProxmoxVmIdentity -Name 'lab-x-dc01' -PoolStart 100 -PoolEnd 105
            $id.VmId | Should -BeGreaterOrEqual 100
            $id.VmId | Should -BeLessOrEqual 105
        }
    }
    It 'rejects empty name and inverted pool' {
        InModuleScope WorkLab.Proxmox {
            { Get-WorkLabProxmoxVmIdentity -Name '' } | Should -Throw
            { Get-WorkLabProxmoxVmIdentity -Name 'x' -PoolStart 50 -PoolEnd 10 } | Should -Throw
        }
    }
}

Describe 'Resolve-WorkLabProxmoxContext' {
    It 'requires Server but leaves op-specific options optional' {
        InModuleScope WorkLab.Proxmox {
            { Resolve-WorkLabProxmoxContext -Context @{ Options = @{} } } |
                Should -Throw -ExpectedMessage '*Options.Server is required*'
            # No Zone/Node required here (validated at point of use).
            $s = Resolve-WorkLabProxmoxContext -Context @{ Options = @{ Server = 'pve.lan' }; Slug = 'demo' }
            $s.Server | Should -Be 'pve.lan'
            $s.Zone | Should -BeNullOrEmpty
            $s.VmIdPoolStart | Should -Be 9000
            $s.VmIdPoolEnd | Should -Be 9999
            $s.Slug | Should -Be 'demo'
        }
    }
    It 'surfaces Node/IsoStorage/DiskStorage and custom pools' {
        InModuleScope WorkLab.Proxmox {
            $s = Resolve-WorkLabProxmoxContext -Context @{ Options = @{
                    Server = 'p'; Node = 'pve1'; IsoStorage = 'local'; DiskStorage = 'local-lvm'
                    VmIdPoolStart = 7000; VmIdPoolEnd = 7100
                } }
            $s.Node | Should -Be 'pve1'
            $s.IsoStorage | Should -Be 'local'
            $s.DiskStorage | Should -Be 'local-lvm'
            $s.VmIdPoolStart | Should -Be 7000
            $s.VmIdPoolEnd | Should -Be 7100
        }
    }
}

Describe 'Assert-WorkLabProxmoxOption' {
    It 'throws naming every missing option' {
        InModuleScope WorkLab.Proxmox {
            { Assert-WorkLabProxmoxOption -Settings @{ Node = 'n' } -Required @('Node', 'DiskStorage', 'IsoStorage') } |
                Should -Throw -ExpectedMessage '*DiskStorage, IsoStorage*'
        }
    }
    It 'passes when all present' {
        InModuleScope WorkLab.Proxmox {
            { Assert-WorkLabProxmoxOption -Settings @{ Node = 'n'; DiskStorage = 'd' } -Required @('Node', 'DiskStorage') } |
                Should -Not -Throw
        }
    }
}

Describe 'Resolve-WorkLabProxmoxVm' {
    It 'returns the VM when present and $null when absent' {
        InModuleScope WorkLab.Proxmox {
            # PveSession is a binary type; strip the constraint so a stand-in
            # session binds to the mocked Get-PveVm.
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123 } }
            $r = Resolve-WorkLabProxmoxVm -Settings @{ Node = 'n' } -Session 'S' -Identity @{ Name = 'lab-demo-dc01'; VmId = 9123 }
            $r.Exists | Should -BeTrue
            $r.VmId | Should -Be 9123

            Mock Get-PveVm -RemoveParameterType 'Session' { }
            (Resolve-WorkLabProxmoxVm -Settings @{ Node = 'n' } -Session 'S' -Identity @{ Name = 'lab-demo-dc01'; VmId = 9123 }).Exists |
                Should -BeFalse
        }
    }
    It 'fast-fails on a VMID/name collision' {
        InModuleScope WorkLab.Proxmox {
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'someone-elses-vm'; VmId = 9123 } }
            { Resolve-WorkLabProxmoxVm -Settings @{ Node = 'n' } -Session 'S' -Identity @{ Name = 'lab-demo-dc01'; VmId = 9123 } } |
                Should -Throw -ExpectedMessage '*already occupied by a different VM*'
        }
    }
}

Describe 'Test-WorkLabProviderConnection capabilities' {
    It 'reports all Phase 1 capabilities REAL' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Test-PveConnection { $true }
            $r = Test-WorkLabProviderConnection -Context @{ Options = @{ Server = 'p'; ApiToken = 't' } }
            $r.Healthy | Should -BeTrue
            $r.Capabilities.Network | Should -BeTrue
            $r.Capabilities.Iso | Should -BeTrue
            $r.Capabilities.Template | Should -BeTrue
            $r.Capabilities.Vm | Should -BeTrue
            $r.Capabilities.Checkpoint | Should -BeTrue
        }
    }
}

Describe 'Network cmdlets still fast-fail without Zone' {
    It 'New-WorkLabProviderNetwork teaches about the missing Zone' {
        { New-WorkLabProviderNetwork -Context @{ Slug = 'demo'; Options = @{ Server = 'pve.lan' } } -Confirm:$false } |
            Should -Throw -ExpectedMessage '*Zone*'
    }
}
