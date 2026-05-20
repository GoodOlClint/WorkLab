# Example config for tools/win-vm-setup.ps1
#
# COPY this file to a location OUTSIDE the repo (or to a path in .gitignore)
# before filling in the Proxmox token, then invoke:
#
#   .\tools\win-vm-setup.ps1 -ConfigFile C:\Users\<you>\worklab-vm.psd1
#
# The script reads everything below; nothing in here is required.

@{
    # SSH public key (single line, the contents of ~/.ssh/id_ed25519.pub).
    # Leave $null to skip key install (you can do it by hand later).
    SSHPublicKey = $null
    # Local account the key belongs to. If the account is in Administrators,
    # the key lands in C:\ProgramData\ssh\administrators_authorized_keys with
    # the restricted ACL Windows OpenSSH requires.
    SSHKeyUser   = 'goodolclint'

    # Env vars set at User scope; the WorkLab gated integration tests
    # self-unskip when these are present. Paths must exist on the VM.
    EnvVars = @{
        WORKLAB_VIRTIO_ISO              = 'C:\iso\virtio-win-0.1.285.iso'
        WORKLAB_IMG_TEST_SOURCE_ISO     = 'C:\ISO\en-us_windows_server_2025_updated_jan_2026_x64_dvd_5cf90374.iso'

        WORKLAB_PROXMOX_TEST_HOST          = 'pve.lab.local'
        WORKLAB_PROXMOX_TEST_PORT          = '8006'
        WORKLAB_PROXMOX_TEST_TOKEN         = 'svc@pve!worklab=00000000-0000-0000-0000-000000000000'
        WORKLAB_PROXMOX_TEST_NODE          = 'pve'
        WORKLAB_PROXMOX_TEST_DISK_STORAGE  = 'local-lvm'
        WORKLAB_PROXMOX_TEST_ISO_STORAGE   = 'local'
        WORKLAB_PROXMOX_TEST_ZONE          = 'labzone'
    }
}
