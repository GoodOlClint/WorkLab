function Copy-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Proxmox provider: clone a VM from a template. (REAL, idempotent)

    .DESCRIPTION
        Full-clones a template into a new VM with a derived VMID. Idempotent:
        if the target VM already exists it is returned unchanged.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER TemplateName
        Source template name.

    .PARAMETER VmName
        New WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER Linked
        Create a linked clone instead of a full (independent) clone.

    .PARAMETER Start
        Power the clone on after creation.

    .EXAMPLE
        Copy-WorkLabProviderVm -Context $c -TemplateName lab-base-tpl01 -VmName lab-twoforest-dc01

    .OUTPUTS
        pscustomobject normalized VM (with Existed flag).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$TemplateName,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter()][switch]$Linked,
        [Parameter()][switch]$Start,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    $settings = $t.Settings; $session = $t.Session; $id = $t.Identity

    if ($t.Resolved.Exists) {
        Write-Warning "VM '$VmName' (VMID $($id.VmId)) already exists; reconciled (no change)."
        return (ConvertTo-WorkLabProxmoxVm -Vm $t.Resolved.Vm -Node $settings.Node |
            Add-Member -NotePropertyName Existed -NotePropertyValue $true -PassThru)
    }

    $tpl = Resolve-WorkLabProxmoxTemplate -Settings $settings -Session $session -Name $TemplateName
    if (-not $tpl) {
        throw "Template '$TemplateName' not found. Create it first: Export-WorkLabProviderTemplate -Context <ctx> -VmName <source>."
    }

    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId)) from '$TemplateName'", 'New-PveVmFromTemplate')) {
        $clone = @{
            TemplateNode = $settings.Node
            VmId         = $tpl.VmId
            NewVmId      = $id.VmId
            NewName      = $VmName
            Wait         = $true
            Session      = $session
            Confirm      = $false
            ErrorAction  = 'Stop'
        }
        if (-not $Linked) { $clone['Full'] = $true }
        New-PveVmFromTemplate @clone

        # Enable the QEMU guest agent on the clone. Proxmox returns "No QEMU
        # guest agent configured" on every agent API call unless the VM has
        # agent=1 set — independent of whether qemu-ga is actually running in
        # the guest (it is; the image bakes it in). Without this the guest
        # channel (Test/Invoke/Write/Read) never works and the reachability
        # wait times out. (No 'boot' key here, so the PSProxmoxVE
        # device-reparse bug — see WorkLab New-WorkLabProviderVm — doesn't apply.)
        # Empty the install CD: the clone inherits the template's sata0, which
        # points at the build ISO that New-WorkLabImageTemplate deletes after the
        # build. Booting a clone with a CD-ROM referencing a missing ISO fails
        # ("Could not open ..."), so swap it for an empty drive (kept, not
        # removed, so the boot order's sata0 entry stays valid).
        $agentCfg = @{ agent = '1'; sata0 = 'none,media=cdrom' }

        # The template's NIC may reference a deleted ephemeral build VNet.
        # When cloning into a lab (Context.Slug present), re-attach net0 to
        # the per-lab VNet so the clone has working networking.
        if (-not [string]::IsNullOrWhiteSpace($settings.Slug)) {
            $net = Get-WorkLabProxmoxNetworkIdentity -Slug $settings.Slug `
                -PoolStart $settings.VlanPoolStart -PoolEnd $settings.VlanPoolEnd
            $agentCfg['net0'] = "virtio,bridge=$($net.Vnet)"
        }
        Set-PveVmConfig -Node $settings.Node -VmId $id.VmId -Session $session -Confirm:$false -ErrorAction Stop `
            -AdditionalConfig $agentCfg

        if ($Start) {
            Start-PveVm -Node $settings.Node -VmId $id.VmId -Wait -Session $session -Confirm:$false -ErrorAction Stop
        }
        $created = (Resolve-WorkLabProxmoxVm -Settings $settings -Session $session -Identity $id).Vm
        return (ConvertTo-WorkLabProxmoxVm -Vm $created -Node $settings.Node |
            Add-Member -NotePropertyName Existed -NotePropertyValue $false -PassThru)
    }
}
