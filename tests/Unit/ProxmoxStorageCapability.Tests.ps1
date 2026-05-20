BeforeAll {
    Import-Module PSProxmoxVE -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force
}

Describe 'Test-WorkLabProxmoxStorageFeature' {
    It 'reports Snapshot supported on <Type>' -ForEach @(
        @{ Type = 'lvmthin' }, @{ Type = 'zfspool' }, @{ Type = 'zfs' },
        @{ Type = 'rbd' },     @{ Type = 'cephfs' },  @{ Type = 'btrfs' }
    ) {
        InModuleScope WorkLab.Proxmox -Parameters @{ Type = $Type } {
            param($Type)
            Mock Get-PveStorage -RemoveParameterType 'Session' { [pscustomobject]@{ Storage = 's'; Type = $Type } }.GetNewClosure()
            $r = Test-WorkLabProxmoxStorageFeature -Settings @{} -Session 'S' -Storage 's' -Feature 'Snapshot'
            $r.Supported  | Should -BeTrue -Because "type '$Type' should support snapshots"
            $r.Suggestion | Should -BeNullOrEmpty
        }
    }
    It 'reports Snapshot NOT supported on <Type> (with a fix suggestion)' -ForEach @(
        @{ Type = 'lvm' },  @{ Type = 'iscsi' }, @{ Type = 'iscsidirect' },
        @{ Type = 'dir' },  @{ Type = 'nfs' },   @{ Type = 'cifs' }
    ) {
        InModuleScope WorkLab.Proxmox -Parameters @{ Type = $Type } {
            param($Type)
            Mock Get-PveStorage -RemoveParameterType 'Session' { [pscustomobject]@{ Storage = 'x'; Type = $Type } }.GetNewClosure()
            $r = Test-WorkLabProxmoxStorageFeature -Settings @{} -Session 'S' -Storage 'x' -Feature 'Snapshot'
            $r.Supported  | Should -BeFalse -Because "type '$Type' is not in the snapshot-capable set"
            $r.Suggestion | Should -Match 'lvmthin'
            $r.Suggestion | Should -Match 'zfspool'
        }
    }
    It 'throws when the storage is unknown to the cluster' {
        InModuleScope WorkLab.Proxmox {
            Mock Get-PveStorage -RemoveParameterType 'Session' { }
            { Test-WorkLabProxmoxStorageFeature -Settings @{} -Session 'S' -Storage 'nope' -Feature 'Snapshot' } |
                Should -Throw -ExpectedMessage "*not found*"
        }
    }
}

Describe 'Get-WorkLabProxmoxVmDiskStorages' {
    It 'extracts distinct storage names from disk lines (in order)' {
        InModuleScope WorkLab.Proxmox {
            $cfg = [pscustomobject]@{
                Scsi0   = 'local-lvm:vm-9001-disk-0,size=60G'
                Scsi1   = 'nas-iSCSI-lvm:vm-9001-disk-1,size=100G'
                Virtio0 = 'local-lvm:vm-9001-disk-2,size=10G'
                Cores   = '2'
            }
            $r = Get-WorkLabProxmoxVmDiskStorages -Config $cfg
            $r | Should -Be @('local-lvm','nas-iSCSI-lvm')
        }
    }
    It 'skips CDROM mounts (media=cdrom)' {
        InModuleScope WorkLab.Proxmox {
            $cfg = [pscustomobject]@{
                Scsi0 = 'lvmthin:vm-9001-disk-0,size=60G'
                Ide2  = 'local:iso/win.iso,media=cdrom'
                Ide3  = 'cloudinit:vm-9001-cloudinit,media=cdrom'
            }
            $r = Get-WorkLabProxmoxVmDiskStorages -Config $cfg
            $r | Should -Be @('lvmthin')
        }
    }
    It 'is case-insensitive on the storage-name dedup' {
        InModuleScope WorkLab.Proxmox {
            $cfg = [pscustomobject]@{
                Scsi0 = 'NAS-iSCSI:vm-1-disk-0,size=10G'
                Scsi1 = 'nas-iscsi:vm-1-disk-1,size=10G'
            }
            (Get-WorkLabProxmoxVmDiskStorages -Config $cfg) | Should -HaveCount 1
        }
    }
}

Describe 'Checkpoint-WorkLabProviderVm fast-fails on snapshot-incapable storage' {
    It 'throws a teaching error when any disk is on a non-snapshot storage' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
            Mock Get-PveVmConfig -RemoveParameterType 'Session' {
                [pscustomobject]@{ Scsi0 = 'nas-iSCSI-lvm:vm-9123-disk-0,size=60G' }
            }
            Mock Get-PveStorage -RemoveParameterType 'Session' { [pscustomobject]@{ Storage = 'nas-iSCSI-lvm'; Type = 'lvm' } }
            Mock New-PveSnapshot { throw 'capability check should have prevented this call' }

            { Checkpoint-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } `
                -VmName lab-demo-dc01 -CheckpointName pre -Confirm:$false } |
                Should -Throw -ExpectedMessage "*does not support snapshots*lvmthin*"
            Should -Invoke New-PveSnapshot -Times 0
        }
    }
    It 'proceeds when every disk is on a snapshot-capable storage' {
        InModuleScope WorkLab.Proxmox {
            Mock Connect-WorkLabProxmox { 'S' }
            Mock Get-PveVm -RemoveParameterType 'Session' { [pscustomobject]@{ Name = 'lab-demo-dc01'; VmId = 9123; Status = 'stopped' } }
            Mock Get-PveVmConfig -RemoveParameterType 'Session' {
                [pscustomobject]@{ Scsi0 = 'tank:vm-9123-disk-0,size=60G' }
            }
            Mock Get-PveStorage -RemoveParameterType 'Session' { [pscustomobject]@{ Storage = 'tank'; Type = 'zfspool' } }
            Mock Get-WorkLabProxmoxSnapshot { }   # snapshot doesn't exist yet
            $script:snapped = 0
            Mock New-PveSnapshot -RemoveParameterType 'Session' { $script:snapped++ }

            $r = Checkpoint-WorkLabProviderVm -Context @{ Options = @{ Server = 'p'; ApiToken = 't'; Node = 'n' } } `
                -VmName lab-demo-dc01 -CheckpointName pre -Confirm:$false
            $r.Existed | Should -BeFalse
            $r.Name | Should -Be 'pre'
            $script:snapped | Should -Be 1
        }
    }
}
