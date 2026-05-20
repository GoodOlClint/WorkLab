function Resolve-WorkLabProxmoxTemplate {
    <#
    .SYNOPSIS
        Find a Proxmox template by name.
    .DESCRIPTION
        Templates are shared images and do not follow the per-VM VMID hash, so
        they are resolved by name among templates only.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][string]$Name
    )

    Get-PveVm -Session $Session -TemplatesOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $Name } |
        Select-Object -First 1
}
