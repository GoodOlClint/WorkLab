function Stop-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Proxmox provider: stop a VM. (REAL, idempotent)

    .DESCRIPTION
        Stops the VM resolved from -VmName. No-op if already stopped or
        absent.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .EXAMPLE
        Stop-WorkLabProviderVm -Context $c -VmName lab-twoforest-dc01

    .OUTPUTS
        pscustomobject: Name, VmId, Status, Changed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    $id = $t.Identity
    if (-not $t.Resolved.Exists) {
        Write-Verbose "VM '$VmName' not present; nothing to stop."
        return [pscustomobject]@{ Name = $VmName; VmId = $id.VmId; Status = 'absent'; Changed = $false }
    }
    if ($t.Resolved.Vm.Status -eq 'stopped') {
        return [pscustomobject]@{ Name = $VmName; VmId = $id.VmId; Status = 'stopped'; Changed = $false }
    }
    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId))", 'Stop-PveVm')) {
        Stop-PveVm -Node $t.Settings.Node -VmId $id.VmId -Wait -Session $t.Session -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ Name = $VmName; VmId = $id.VmId; Status = 'stopped'; Changed = $true }
    }
}
