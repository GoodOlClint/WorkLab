function Start-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Proxmox provider: start a VM. (REAL, idempotent)

    .DESCRIPTION
        Starts the VM resolved from -VmName. No-op if already running.
        Fast-fails if the VM does not exist.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .EXAMPLE
        Start-WorkLabProviderVm -Context $c -VmName lab-twoforest-dc01

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
    if (-not $t.Resolved.Exists) {
        throw "VM '$VmName' not found. Create it first: New-WorkLabProviderVm -Context <ctx> -VmName $VmName."
    }
    $id = $t.Identity
    if ($t.Resolved.Vm.Status -eq 'running') {
        return [pscustomobject]@{ Name = $VmName; VmId = $id.VmId; Status = 'running'; Changed = $false }
    }
    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId))", 'Start-PveVm')) {
        Start-PveVm -Node $t.Settings.Node -VmId $id.VmId -Wait -Session $t.Session -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ Name = $VmName; VmId = $id.VmId; Status = 'running'; Changed = $true }
    }
}
