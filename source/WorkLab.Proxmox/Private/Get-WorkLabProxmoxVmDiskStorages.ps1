function Get-WorkLabProxmoxVmDiskStorages {
    <#
    .SYNOPSIS
        Extract distinct (non-CDROM) storage names from a Proxmox VM config.

    .DESCRIPTION
        Walks every scsi*/virtio*/sata*/ide*/efidisk*/tpmstate* property on
        the config object and parses the leading "<storage>:" prefix. Skips
        any entry tagged `media=cdrom` (those are ISO mounts, not block
        storage that needs snapshot capability).

        Used by Checkpoint-WorkLabProviderVm to capability-check every
        storage the VM actually has a disk on, not just the configured
        DiskStorage default.

    .PARAMETER Config
        The pscustomobject returned by Get-PveVmConfig.

    .OUTPUTS
        [string[]] distinct storage names, in declaration order.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Config
    )

    $diskProps = $Config.PSObject.Properties |
        Where-Object { $_.Name -match '^(Scsi|Virtio|Sata|Ide|Efidisk|Tpmstate)\d+$' }

    $storages = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($p in $diskProps) {
        $value = [string]$p.Value
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value -match '\bmedia=cdrom\b') { continue }
        # "<storage>:<volume-or-size>[,opt=val,...]" -> take everything before the first ':'.
        $storage = ($value -split ':', 2)[0].Trim()
        if ([string]::IsNullOrWhiteSpace($storage)) { continue }
        if ($seen.Add($storage)) { $storages.Add($storage) }
    }
    return [string[]]$storages
}
