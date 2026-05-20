function Remove-WorkLabProviderCheckpoint {
    <#
    .SYNOPSIS
        Proxmox provider: delete a VM snapshot. (REAL, idempotent)

    .DESCRIPTION
        Removes a named snapshot from the resolved VM. Idempotent: a missing
        VM or missing snapshot is a no-op.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER CheckpointName
        Snapshot name to delete.

    .EXAMPLE
        Remove-WorkLabProviderCheckpoint -Context $c -VmName lab-twoforest-dc01 -CheckpointName pre-patch

    .OUTPUTS
        pscustomobject: VmName, Name, Removed.
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
    $id = $t.Identity
    if (-not $t.Resolved.Exists) {
        Write-Verbose "VM '$VmName' not present; nothing to remove."
        return [pscustomobject]@{ VmName = $VmName; Name = $CheckpointName; Removed = $false }
    }

    $snap = Get-WorkLabProxmoxSnapshot -Settings $t.Settings -Session $t.Session -VmId $id.VmId -Name $CheckpointName
    if (-not $snap) {
        Write-Verbose "Snapshot '$CheckpointName' not present on '$VmName'; nothing to remove."
        return [pscustomobject]@{ VmName = $VmName; Name = $CheckpointName; Removed = $false }
    }

    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId))", "Remove-PveSnapshot '$CheckpointName'")) {
        Remove-PveSnapshot -Node $t.Settings.Node -VmId $id.VmId -Name $CheckpointName `
            -Wait -Session $t.Session -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ VmName = $VmName; Name = $CheckpointName; Removed = $true }
    }
}
