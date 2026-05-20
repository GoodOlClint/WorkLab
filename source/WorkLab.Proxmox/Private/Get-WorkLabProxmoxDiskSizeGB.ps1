function Get-WorkLabProxmoxDiskSizeGB {
    <#
    .SYNOPSIS
        Normalize a human-friendly disk-size string to a bare integer-GB
        string that every Proxmox storage type accepts.

    .DESCRIPTION
        Accepts:
          - bare integer:        '60'  -> '60'
          - integer + G suffix:  '60G' -> '60'  (G or g; the common form)
          - integer + GB suffix: '60GB' -> '60' (paranoia)
          - integer + T suffix:  '2T'  -> '2048' (terabyte convenience)
          - whitespace tolerated, case-insensitive

        Rejects fractional sizes ('1.5G') and units below G (M/K); Proxmox
        qemu disk creation is integer-GB internally and our cmdlets do not
        expose sub-GB sizing.

        Background: PSProxmoxVE's New-PveVm -DiskSize docs say "e.g. 32G"
        but pass the value through to the Proxmox API verbatim. LVM-backed
        storages then parse the unit as part of an existing volume name and
        the API throws "unable to parse lvm volume name '1G'". Filed
        upstream; we normalize defensively here so every storage type works.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$DiskSize
    )
    $s = $DiskSize.Trim()
    if ($s -match '^(?<n>\d+)\s*(?<u>G|GB|T|TB)?$') {
        $n = [int]$matches['n']
        $u = if ($matches['u']) { $matches['u'].ToUpperInvariant() } else { 'G' }
        $gb = switch -Regex ($u) {
            '^G(B)?$' { $n }
            '^T(B)?$' { $n * 1024 }
        }
        return [string]$gb
    }
    throw "Invalid DiskSize '$DiskSize'. Use integer GB (e.g. '60' or '60G'); fractional sizes and units below G are not supported."
}
