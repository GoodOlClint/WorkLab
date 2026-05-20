function Get-WorkLabProxmoxVmIdentity {
    <#
    .SYNOPSIS
        Deterministically derive the Proxmox VMID for a WorkLab VM name.
    .DESCRIPTION
        Proxmox is VMID-keyed; WorkLab identity is name-based
        (lab-<slug>-<role>NN). The VMID is a stable hash of the name folded
        into a configurable pool [PoolStart, PoolEnd] (default 9000-9999),
        mirroring the Phase 0 VLAN-tag scheme. This gives O(1) idempotency
        and collision detection without a name->id lookup.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][int]$PoolStart = 9000,
        [Parameter()][int]$PoolEnd = 9999
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Get-WorkLabProxmoxVmIdentity requires a non-empty VM Name.'
    }
    if ($PoolEnd -lt $PoolStart) {
        throw "Invalid VMID pool: end ($PoolEnd) < start ($PoolStart)."
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Name.ToLowerInvariant()))
    }
    finally {
        $sha.Dispose()
    }

    $u32 = [System.BitConverter]::ToUInt32($bytes, 0)
    $span = [uint32]($PoolEnd - $PoolStart + 1)
    $vmid = $PoolStart + [int]($u32 % $span)

    @{ Name = $Name; VmId = $vmid }
}
