function Remove-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Proxmox provider: remove a VM. (REAL, idempotent)

    .DESCRIPTION
        Removes the VM resolved from -VmName, purging its disks. No-op if the
        VM is absent.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .EXAMPLE
        Remove-WorkLabProviderVm -Context $c -VmName lab-twoforest-dc01

    .OUTPUTS
        pscustomobject: Name, VmId, Removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    $id = $t.Identity
    if (-not $t.Resolved.Exists) {
        Write-Verbose "VM '$VmName' not present; nothing to remove."
        return [pscustomobject]@{ Name = $VmName; VmId = $id.VmId; Removed = $false }
    }
    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId))", 'Remove-PveVm')) {
        Remove-PveVm -Node $t.Settings.Node -VmId $id.VmId -Purge -Force -Wait `
            -Session $t.Session -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ Name = $VmName; VmId = $id.VmId; Removed = $true }
    }
}
