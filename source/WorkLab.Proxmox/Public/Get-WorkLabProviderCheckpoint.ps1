function Get-WorkLabProviderCheckpoint {
    <#
    .SYNOPSIS
        Proxmox provider: list a VM's snapshots. (REAL)

    .DESCRIPTION
        Returns the resolved VM's snapshots (the synthetic 'current' is
        excluded). Nothing is returned if the VM is absent.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER CheckpointName
        Optional snapshot-name filter.

    .EXAMPLE
        Get-WorkLabProviderCheckpoint -Context $c -VmName lab-twoforest-dc01

    .OUTPUTS
        pscustomobject normalized snapshot(s).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter()][string]$CheckpointName,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    if (-not $t.Resolved.Exists) { return }
    $id = $t.Identity

    Get-WorkLabProxmoxSnapshot -Settings $t.Settings -Session $t.Session -VmId $id.VmId -Name $CheckpointName |
        ForEach-Object {
            [pscustomobject]@{
                Provider    = 'Proxmox'
                VmName      = $VmName
                VmId        = $id.VmId
                Name        = $_.Name
                Description = $_.Description
                Raw         = $_
            }
        }
}
