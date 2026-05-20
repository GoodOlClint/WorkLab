function Restore-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Proxmox provider: restore a VM to a snapshot. (REAL)

    .DESCRIPTION
        Rolls the resolved VM back to a named snapshot. Fast-fails if the VM
        or the snapshot does not exist.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER CheckpointName
        Snapshot name to restore.

    .EXAMPLE
        Restore-WorkLabProviderVm -Context $c -VmName lab-twoforest-dc01 -CheckpointName pre-patch

    .OUTPUTS
        pscustomobject: Provider, VmName, VmId, Name, Restored.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$CheckpointName,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    if (-not $t.Resolved.Exists) {
        throw "VM '$VmName' not found."
    }
    $settings = $t.Settings; $session = $t.Session; $id = $t.Identity

    $snap = Get-WorkLabProxmoxSnapshot -Settings $settings -Session $session -VmId $id.VmId -Name $CheckpointName
    if (-not $snap) {
        throw "Snapshot '$CheckpointName' not found on '$VmName'. List with Get-WorkLabProviderCheckpoint."
    }

    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId))", "Restore-PveSnapshot '$CheckpointName'")) {
        Restore-PveSnapshot -Node $settings.Node -VmId $id.VmId -Name $CheckpointName `
            -Wait -Session $session -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ Provider = 'Proxmox'; VmName = $VmName; VmId = $id.VmId; Name = $CheckpointName; Restored = $true }
    }
}
