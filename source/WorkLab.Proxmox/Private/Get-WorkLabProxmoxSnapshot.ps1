function Get-WorkLabProxmoxSnapshot {
    <#
    .SYNOPSIS
        List a VM's snapshots, optionally one by name.
    .DESCRIPTION
        Wraps Get-PveSnapshot. Proxmox includes a synthetic 'current' pseudo
        snapshot in listings; it is filtered out unless asked for by name.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][hashtable]$Settings,
        [Parameter(Mandatory)][object]$Session,
        [Parameter(Mandatory)][int]$VmId,
        [Parameter()][string]$Name
    )

    $snaps = Get-PveSnapshot -Node $Settings.Node -VmId $VmId -Session $Session -ErrorAction SilentlyContinue

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        return ($snaps | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
    }
    $snaps | Where-Object { $_.Name -ne 'current' }
}
