function Resolve-WorkLabProxmoxVm {
    <#
    .SYNOPSIS
        Look up a WorkLab VM on Proxmox by its derived identity.
    .DESCRIPTION
        Central idempotency seam: every VM-scoped op resolves the VM through
        here. Returns the Proxmox VM object (or $null) alongside the derived
        identity. Also fails fast on a VMID/name collision: a VM occupying the
        derived VMID whose name differs is not ours.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][hashtable]$Identity
    )

    $vm = Get-PveVm -Node $Settings.Node -VmId $Identity.VmId -Session $Session -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($vm -and $vm.Name -and $vm.Name -ne $Identity.Name) {
        throw "VMID $($Identity.VmId) (derived for '$($Identity.Name)') is already occupied by a different VM '$($vm.Name)'. Choose a different lab slug or widen Options.VmIdPool{Start,End}."
    }

    [pscustomobject]@{
        Identity = $Identity
        VmId     = $Identity.VmId
        Name     = $Identity.Name
        Vm       = $vm
        Exists   = [bool]$vm
    }
}
