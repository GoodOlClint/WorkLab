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
        # PSProxmoxVE / the Proxmox API reject a unit-suffixed disk size on
        # LVM-backed storages (lvm, lvm-thin) -- they read "60G" as a volume
        # name ("unable to parse lvm volume name '1G'") and want a bare integer
        # in GB. File-backed storages tolerate either. Normalize to bare GB for
        # the scsi0 disk spec below.
        $normalizedDiskSize = Get-WorkLabProxmoxDiskSizeGB -DiskSize $DiskSize

        # Create the VM DISKLESS. New-PveVm can only make a plain virtio0 disk
        # with no IO options; we add the boot disk below on a tuned
        # virtio-scsi-single controller instead (New-PveVm has no params for the
        # controller type or any disk IO option -- filed upstream).
        $newVm = @{
            Node        = $settings.Node
            VmId        = $id.VmId
            Name        = $VmName
            Memory      = $MemoryMB
            Cores       = $Cores
            Bridge      = $net.Vnet
            Wait        = $true
            Session     = $session
            Confirm     = $false
            ErrorAction = 'Stop'
        }
        if ($OsType) { $newVm['OsType'] = $OsType }
        if ($Bios) { $newVm['Bios'] = $Bios }
        # OVMF (UEFI) requires the q35 machine type; pair them automatically so
        # callers only have to ask for -Bios ovmf. Also force a CPU model that
        # exposes x86-64-v2 (POPCNT/SSE4.2): Windows 11 / Server 2025 WinPE
        # triple-faults at the boot logo on the default kvm64 CPU (no POPCNT),
        # which looks like a boot loop. All matches the proven Packer template
        # (bios=ovmf, machine=pc-q35-*, ostype=win11, cpu=x86-64-v2-AES).
        if ($Bios -eq 'ovmf') {
            $newVm['Machine'] = 'q35'
            $newVm['CpuType'] = 'x86-64-v2-AES'
        }
        # Deliberately do NOT start as part of create. The disk, EFI vars, and
        # CD-ROM + boot order must be in place BEFORE first power-on, or the VM
        # boots with no bootable device and bootloops. Configure fully, start
        # explicitly below.
        New-PveVm @newVm

        # Boot disk on virtio-scsi-single with full IO tuning:
        #   iothread=1   dedicated IO thread (needs virtio-scsi-single or virtio-blk)
        #   aio=native   native Linux AIO (pairs with raw/LVM-thin)
        #   ssd=1        present as SSD (TRIM hints; needs a SCSI/SATA bus -- virtio-blk rejects ssd)
        #   discard=on   pass TRIM through so thin storage reclaims space
        # Same call adds the OVMF EFI vars disk (NVRAM; without it a UEFI VM has
        # no firmware store and can't persist/boot a UEFI OS -- efitype=4m is the
        # modern 4MB OVMF, pre-enrolled-keys=0 leaves Secure Boot unenrolled so
        # unattended media isn't signature-gated) and enables the guest-agent
        # channel (agent=1). The image's pre-sysprep FirstLogon installs the
        # virtio-serial driver + qemu-ga; having the channel present here lets the
        # agent bind and come up on the template. Clones get agent=1 of their own
        # (Copy-WorkLabProviderVm).
        $diskCfg = @{
            scsihw = 'virtio-scsi-single'
            scsi0  = "$($settings.DiskStorage):$normalizedDiskSize,iothread=1,aio=native,ssd=1,discard=on"
            agent  = '1'
        }
        if ($Bios -eq 'ovmf') {
            $diskCfg['efidisk0'] = "$($settings.DiskStorage):1,efitype=4m,pre-enrolled-keys=0"
        }
        Set-PveVmConfig -Node $settings.Node -VmId $id.VmId -Session $session -Confirm:$false -ErrorAction Stop `
            -AdditionalConfig $diskCfg

        # Boot from the disk first. Name ONLY scsi0 in the boot order: a
        # config-created scsi0 is NOT auto-added to the order (so we must), while
        # naming the CD (ide2) here would trip a PSProxmoxVE serialization bug
        # that re-emits ordered devices as malformed drive params ("ide2: unable
        # to parse drive options" -- filed upstream). The ide2 added below IS
        # auto-appended by Proxmox, landing after scsi0 (CD-last): the empty disk
        # is non-bootable so firmware falls through to the CD on first boot, then
        # the installed disk boots first on every later reboot -- no CD reboot
        # loop, no need to detach the ISO mid-build.
        Set-PveVmConfig -Node $settings.Node -VmId $id.VmId -Session $session -Confirm:$false -ErrorAction Stop `
            -AdditionalConfig @{ boot = 'order=scsi0' }

        if ($IsoName) {
            # Attach the install ISO as a CD-ROM; Proxmox auto-appends it to the
            # boot order after scsi0 (see the boot-order note above).
            Set-PveVmConfig -Node $settings.Node -VmId $id.VmId -Session $session -Confirm:$false -ErrorAction Stop `
                -AdditionalConfig @{ ide2 = "$($settings.IsoStorage):iso/$IsoName,media=cdrom" }
        }

        if ($Start) {
            Start-PveVm -Node $settings.Node -VmId $id.VmId -Wait -Session $session -Confirm:$false -ErrorAction Stop
        }

        $created = (Resolve-WorkLabProxmoxVm -Settings $settings -Session $session -Identity $id).Vm
        return (ConvertTo-WorkLabProxmoxVm -Vm $created -Node $settings.Node |
            Add-Member -NotePropertyName Existed -NotePropertyValue $false -PassThru)
    }
}
