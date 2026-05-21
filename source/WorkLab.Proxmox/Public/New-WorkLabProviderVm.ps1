function New-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Proxmox provider: create a VM from an ISO. (REAL, idempotent)

    .DESCRIPTION
        Creates a qemu VM with a derived VMID, attaches its NIC to the
        per-lab SDN VNet (which must already exist), and optionally attaches a
        registered ISO as a boot CD-ROM. Idempotent: an existing VM with the
        derived identity is returned unchanged.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node/DiskStorage[/IsoStorage])
        and Slug (used to resolve the per-lab network bridge).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER Cores
        vCPU count (default 2).

    .PARAMETER MemoryMB
        RAM in MB (default 4096).

    .PARAMETER DiskSize
        Primary disk size, Proxmox notation (default '60G').

    .PARAMETER OsType
        Proxmox ostype (optional; PSProxmoxVE default if omitted).

    .PARAMETER Bios
        Proxmox bios (optional; e.g. 'ovmf').

    .PARAMETER IsoName
        Registered ISO file to attach as a boot CD-ROM (requires IsoStorage).

    .PARAMETER Start
        Power the VM on after creation.

    .EXAMPLE
        New-WorkLabProviderVm -Context $c -VmName lab-twoforest-dc01 -IsoName win2025.iso -Start

    .OUTPUTS
        pscustomobject normalized VM (with Existed flag).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter()][int]$Cores = 2,
        [Parameter()][int]$MemoryMB = 4096,
        [Parameter()][string]$DiskSize = '60G',
        [Parameter()][string]$OsType,
        [Parameter()][string]$Bios,
        [Parameter()][string]$IsoName,
        [Parameter()][switch]$Start,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $require = @('Node', 'DiskStorage')
    if ($IsoName) { $require += 'IsoStorage' }
    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption $require
    $settings = $t.Settings; $session = $t.Session; $id = $t.Identity

    if ($t.Resolved.Exists) {
        Write-Warning "VM '$VmName' (VMID $($id.VmId)) already exists; reconciled (no change)."
        return (ConvertTo-WorkLabProxmoxVm -Vm $t.Resolved.Vm -Node $settings.Node |
            Add-Member -NotePropertyName Existed -NotePropertyValue $true -PassThru)
    }

    if ([string]::IsNullOrWhiteSpace($settings.Slug)) {
        throw "Proxmox New-WorkLabProviderVm requires Context.Slug to resolve the per-lab network bridge."
    }
    $net = Get-WorkLabProxmoxNetworkIdentity -Slug $settings.Slug `
        -PoolStart $settings.VlanPoolStart -PoolEnd $settings.VlanPoolEnd
    if (-not (Get-PveSdnVnet -Vnet $net.Vnet -Session $session -ErrorAction SilentlyContinue)) {
        throw "Per-lab network '$($net.Vnet)' does not exist. Create it first: New-WorkLabProviderNetwork -Context <ctx-with-Slug>."
    }

    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId))", 'New-PveVm')) {
        # PSProxmoxVE accepts "60G"-style strings but passes them through to
        # the Proxmox API verbatim. LVM-backed storages (lvm, lvm-thin) reject
        # the unit and interpret the suffix as a volume name ("unable to parse
        # lvm volume name '1G'"); they want a bare integer in GB. File-backed
        # storages tolerate either. Normalize here so we send what every
        # storage type accepts.
        $normalizedDiskSize = Get-WorkLabProxmoxDiskSizeGB -DiskSize $DiskSize
        $newVm = @{
            Node        = $settings.Node
            VmId        = $id.VmId
            Name        = $VmName
            Memory      = $MemoryMB
            Cores       = $Cores
            DiskSize    = $normalizedDiskSize
            DiskStorage = $settings.DiskStorage
            Bridge      = $net.Vnet
            Wait        = $true
            Session     = $session
            Confirm     = $false
            ErrorAction = 'Stop'
        }
        if ($OsType) { $newVm['OsType'] = $OsType }
        if ($Bios) { $newVm['Bios'] = $Bios }
        # OVMF (UEFI) requires the q35 machine type; pair them automatically so
        # callers only have to ask for -Bios ovmf. Matches the proven Packer
        # template (bios=ovmf, machine=pc-q35-*, ostype=win11).
        if ($Bios -eq 'ovmf') { $newVm['Machine'] = 'q35' }
        # Deliberately do NOT start as part of create. When an ISO is attached
        # the CD-ROM device + boot order must be in place BEFORE first power-on,
        # otherwise the VM boots with no bootable device and bootloops ("no
        # available device"). Configure fully, then start explicitly below.
        New-PveVm @newVm

        # OVMF needs an EFI vars disk (NVRAM) or the VM has no UEFI firmware
        # store and can't persist/boot a UEFI OS. New-PveVm doesn't create one,
        # so add it here. efitype=4m is the modern 4MB OVMF; pre-enrolled-keys=0
        # leaves Secure Boot unenrolled so unattended install media isn't
        # signature-gated. (Verified the <storage>:1 create syntax allocates a
        # 4MB efidisk on this cluster.)
        if ($Bios -eq 'ovmf') {
            Set-PveVmConfig -Node $settings.Node -VmId $id.VmId -Session $session -Confirm:$false -ErrorAction Stop `
                -AdditionalConfig @{
                    efidisk0 = "$($settings.DiskStorage):1,efitype=4m,pre-enrolled-keys=0"
                }
        }

        if ($IsoName) {
            # Attach the install ISO as a CD-ROM. Set ONLY ide2 — do not set the
            # 'boot' key in the same (or a separate) Set-PveVmConfig call:
            # PSProxmoxVE re-emits every disk device named in the boot-order
            # string as a (malformed) drive parameter, so any call carrying
            # 'boot' fails with "<dev>: unable to parse drive options" (filed
            # upstream). Attaching ide2 alone makes Proxmox auto-append it to
            # the existing boot order (e.g. 'order=virtio0;net0;ide2'). CD-last
            # is exactly what an unattended Windows install wants: the empty OS
            # disk is non-bootable so firmware falls through to the CD on first
            # boot, and once Windows is installed the disk boots first on every
            # subsequent reboot — no "Setup keeps rebooting into the CD" loop,
            # and no need to detach the ISO mid-build.
            Set-PveVmConfig -Node $settings.Node -VmId $id.VmId -Session $session -Confirm:$false -ErrorAction Stop `
                -AdditionalConfig @{
                    ide2 = "$($settings.IsoStorage):iso/$IsoName,media=cdrom"
                }
        }

        if ($Start) {
            Start-PveVm -Node $settings.Node -VmId $id.VmId -Wait -Session $session -Confirm:$false -ErrorAction Stop
        }

        $created = (Resolve-WorkLabProxmoxVm -Settings $settings -Session $session -Identity $id).Vm
        return (ConvertTo-WorkLabProxmoxVm -Vm $created -Node $settings.Node |
            Add-Member -NotePropertyName Existed -NotePropertyValue $false -PassThru)
    }
}
