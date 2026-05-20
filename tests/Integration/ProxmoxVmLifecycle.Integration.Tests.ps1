# Gated Proxmox VM-lifecycle integration test (lightweight, no OS boot).
# Self-skips unless WORKLAB_PROXMOX_TEST_HOST is set.
#
# Required env:
#   WORKLAB_PROXMOX_TEST_HOST          Proxmox host/FQDN
#   WORKLAB_PROXMOX_TEST_TOKEN         API token  user@realm!tokenid=uuid
#   WORKLAB_PROXMOX_TEST_NODE          target node
#   WORKLAB_PROXMOX_TEST_DISK_STORAGE  storage for the VM disk
#   WORKLAB_PROXMOX_TEST_ZONE          pre-created SDN VLAN zone (for the lab VNet)
# Optional:
#   WORKLAB_PROXMOX_TEST_PORT          (default 8006)

$script:ProxmoxGate = -not [string]::IsNullOrWhiteSpace($env:WORKLAB_PROXMOX_TEST_HOST)

Describe 'Proxmox VM lifecycle (lightweight)' -Skip:(-not $script:ProxmoxGate) {

    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../../source/WorkLab.Proxmox/WorkLab.Proxmox.psd1') -Force

        $script:Slug = 'it' + (-join ((48..57 + 97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ }))
        $script:VmName = "lab-$($script:Slug)-it01"
        $opts = @{
            Server               = $env:WORKLAB_PROXMOX_TEST_HOST
            Port                 = if ($env:WORKLAB_PROXMOX_TEST_PORT) { [int]$env:WORKLAB_PROXMOX_TEST_PORT } else { 8006 }
            ApiToken             = $env:WORKLAB_PROXMOX_TEST_TOKEN
            Node                 = $env:WORKLAB_PROXMOX_TEST_NODE
            DiskStorage          = $env:WORKLAB_PROXMOX_TEST_DISK_STORAGE
            Zone                 = $env:WORKLAB_PROXMOX_TEST_ZONE
            SkipCertificateCheck = $true
        }
        $script:Ctx = @{ Slug = $script:Slug; Options = $opts }
        New-WorkLabProviderNetwork -Context $script:Ctx -Confirm:$false | Out-Null
    }

    AfterAll {
        try { Remove-WorkLabProviderVm -Context $script:Ctx -VmName $script:VmName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Remove-WorkLabProviderNetwork -Context $script:Ctx -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    It 'creates the VM on the per-lab network (idempotent)' {
        $vm = New-WorkLabProviderVm -Context $script:Ctx -VmName $script:VmName -Cores 1 -MemoryMB 512 -DiskSize 1G -Confirm:$false
        $vm.Provider | Should -Be 'Proxmox'
        $vm.Name | Should -Be $script:VmName
        $vm.Existed | Should -BeFalse

        $again = New-WorkLabProviderVm -Context $script:Ctx -VmName $script:VmName -Cores 1 -MemoryMB 512 -DiskSize 1G -Confirm:$false
        $again.Existed | Should -BeTrue
    }

    It 'gets the VM back' {
        $got = Get-WorkLabProviderVm -Context $script:Ctx -VmName $script:VmName
        $got | Should -Not -BeNullOrEmpty
        $got.Name | Should -Be $script:VmName
    }

    It 'checkpoints, lists, restores, then removes the checkpoint' {
        # Self-skip when the configured DiskStorage doesn't support snapshots
        # (plain LVM, iSCSI-LVM, raw on dir/nfs, etc.). The framework's
        # Checkpoint cmdlet now fast-fails with a teaching error in that
        # case; verifying that path requires a snapshot-capable storage.
        $cap = & (Get-Module WorkLab.Proxmox) {
            param($DiskStorage, $Session)
            $session = Connect-WorkLabProxmox -Settings ([pscustomobject]@{
                Server = $env:WORKLAB_PROXMOX_TEST_HOST
                Port = if ($env:WORKLAB_PROXMOX_TEST_PORT) { [int]$env:WORKLAB_PROXMOX_TEST_PORT } else { 8006 }
                ApiToken = $env:WORKLAB_PROXMOX_TEST_TOKEN
                SkipCertificateCheck = $true
            })
            Test-WorkLabProxmoxStorageFeature -Settings @{} -Session $session -Storage $DiskStorage -Feature 'Snapshot'
        } $env:WORKLAB_PROXMOX_TEST_DISK_STORAGE
        if (-not $cap.Supported) {
            Set-ItResult -Skipped -Because ("storage '$($cap.Storage)' (type '$($cap.Type)') doesn't support snapshots; set WORKLAB_PROXMOX_TEST_DISK_STORAGE to one of: $($cap.Suggestion)")
            return
        }

        (Checkpoint-WorkLabProviderVm -Context $script:Ctx -VmName $script:VmName -CheckpointName pre -Confirm:$false).Existed | Should -BeFalse
        (Get-WorkLabProviderCheckpoint -Context $script:Ctx -VmName $script:VmName).Name | Should -Contain 'pre'
        (Restore-WorkLabProviderVm -Context $script:Ctx -VmName $script:VmName -CheckpointName pre -Confirm:$false).Restored | Should -BeTrue
        (Remove-WorkLabProviderCheckpoint -Context $script:Ctx -VmName $script:VmName -CheckpointName pre -Confirm:$false).Removed | Should -BeTrue
        Get-WorkLabProviderCheckpoint -Context $script:Ctx -VmName $script:VmName | Should -BeNullOrEmpty
    }

    It 'removes the VM and then reports absence' {
        (Remove-WorkLabProviderVm -Context $script:Ctx -VmName $script:VmName -Confirm:$false).Removed | Should -BeTrue
        Get-WorkLabProviderVm -Context $script:Ctx -VmName $script:VmName | Should -BeNullOrEmpty
    }
}
