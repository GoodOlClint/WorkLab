function Get-WorkLabProxmoxNetworkIdentity {
    <#
    .SYNOPSIS
        Deterministically derive the per-lab SDN VNet id + VLAN tag.
    .DESCRIPTION
        Proxmox SDN VNet ids are <=8 chars, must start with a letter. Slugs
        are 3-12 chars and may start with a digit, so the VNet id is
        'l' + 7 chars of a stable hash of the slug. The VLAN tag is the slug
        hash folded into [PoolStart, PoolEnd] inclusive.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Slug,
        [Parameter()][int]$PoolStart = 100,
        [Parameter()][int]$PoolEnd = 200
    )

    if ($PoolEnd -lt $PoolStart) {
        throw "Invalid VLAN pool: end ($PoolEnd) < start ($PoolStart)."
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Slug.ToLowerInvariant()))
    }
    finally {
        $sha.Dispose()
    }

    # First 4 bytes -> unsigned int for tag folding.
    $u32 = [System.BitConverter]::ToUInt32($bytes, 0)
    $span = ($PoolEnd - $PoolStart + 1)
    $tag = $PoolStart + [int]($u32 % [uint32]$span)

    # base36 of the digest, take 7 chars, prefix 'l'.
    $big = [System.Numerics.BigInteger]::Abs([System.Numerics.BigInteger]::new($bytes[0..15] + [byte]0))
    $alphabet = '0123456789abcdefghijklmnopqrstuvwxyz'
    $sb = [System.Text.StringBuilder]::new()
    while ($big -gt 0 -and $sb.Length -lt 7) {
        $rem = [int]($big % 36)
        [void]$sb.Insert(0, $alphabet[$rem])
        $big = [System.Numerics.BigInteger]::Divide($big, 36)
    }
    $suffix = $sb.ToString().PadLeft(7, '0')
    $vnet = "l$suffix"

    @{ Vnet = $vnet; Tag = $tag }
}
