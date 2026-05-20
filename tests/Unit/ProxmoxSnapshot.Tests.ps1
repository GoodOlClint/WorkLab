BeforeAll {
    Import-Module PSProxmoxVE -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force
}

Describe 'Checkpoint-WorkLabProviderVm' {
    It 'throws when the VM is absent' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { }
            { Checkpoint-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01 -CheckpointName s1 -Confirm:$false } |
                Should -Throw -ExpectedMessage '*not found*'
        }
    }

    It 'creates when absent and reconciles when the snapshot exists' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
            $script:made = 0
            Mock New-PveSnapshot -RemoveParameterType 'Session' { $script:made++ }
            Mock Get-PveSnapshot -RemoveParameterType 'Session' { }   # none yet
            $ctx = @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } }
            $r = Checkpoint-WorkLabProviderVm -Context $ctx -VmName lab-demo-dc01 -CheckpointName pre-patch -Confirm:$false
            $r.Existed | Should -BeFalse
            $script:made | Should -Be 1

            Mock Get-PveSnapshot -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'pre-patch' } }
            $r2 = Checkpoint-WorkLabProviderVm -Context $ctx -VmName lab-demo-dc01 -CheckpointName pre-patch -Confirm:$false
            $r2.Existed | Should -BeTrue
            $script:made | Should -Be 1
        }
    }
}

Describe 'Restore-WorkLabProviderVm' {
    It 'throws when the snapshot is missing, restores when present' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123 } }
            $script:restored = 0
            Mock Restore-PveSnapshot -RemoveParameterType 'Session' { $script:restored++ }
            $ctx = @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } }

            Mock Get-PveSnapshot -RemoveParameterType 'Session' { }
            { Restore-WorkLabProviderVm -Context $ctx -VmName lab-demo-dc01 -CheckpointName nope -Confirm:$false } |
                Should -Throw -ExpectedMessage '*not found*'

            Mock Get-PveSnapshot -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'pre-patch' } }
            (Restore-WorkLabProviderVm -Context $ctx -VmName lab-demo-dc01 -CheckpointName pre-patch -Confirm:$false).Restored | Should -BeTrue
            $script:restored | Should -Be 1
        }
    }
}

Describe 'Get/Remove-WorkLabProviderCheckpoint' {
    It 'lists snapshots excluding the synthetic current' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123 } }
            Mock Get-PveSnapshot -RemoveParameterType 'Session' {
                [pscustomobject]@{ Name = 'pre-patch'; Description = 'before' }
                [pscustomobject]@{ Name = 'current'; Description = 'you are here' }
            }
            $r = Get-WorkLabProviderCheckpoint -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } -VmName lab-demo-dc01
            ($r | Measure-Object).Count | Should -Be 1
            $r.Name | Should -Be 'pre-patch'
            $r.Provider | Should -Be 'Proxmox'
        }
    }

    It 'removes when present and no-ops when absent' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123 } }
            $script:rm = 0
            Mock Remove-PveSnapshot -RemoveParameterType 'Session' { $script:rm++ }
            $ctx = @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } }

            Mock Get-PveSnapshot -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'pre-patch' } }
            (Remove-WorkLabProviderCheckpoint -Context $ctx -VmName lab-demo-dc01 -CheckpointName pre-patch -Confirm:$false).Removed | Should -BeTrue
            $script:rm | Should -Be 1

            Mock Get-PveSnapshot -RemoveParameterType 'Session' { }
            (Remove-WorkLabProviderCheckpoint -Context $ctx -VmName lab-demo-dc01 -CheckpointName gone -Confirm:$false).Removed | Should -BeFalse
            $script:rm | Should -Be 1
        }
    }
}
