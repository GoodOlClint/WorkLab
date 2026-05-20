function Assert-WorkLabProxmoxOption {
    <#
    .SYNOPSIS
        Fast-fail unless the named resolved settings are present.
    .DESCRIPTION
        Op-specific options are validated where they are used, not globally,
        so a network-only or VM-only caller is not forced to supply unrelated
        options. The error names every missing option and a concrete fix.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][string[]]$Required
    )

    $missing = foreach ($name in $Required) {
        if ([string]::IsNullOrWhiteSpace([string]$Settings[$name])) { $name }
    }
    if ($missing) {
        $list = ($missing -join ', ')
        throw "Proxmox provider is missing required option(s): $list. Supply them via Register-WorkLabProvider -Name Proxmox -Options @{ Server='pve.lan'; ApiToken='user@realm!id=uuid'; Node='pve1'; DiskStorage='local-lvm'; IsoStorage='local'; Zone='labzone' } (only the options your operation needs are required)."
    }
}
