function Checkpoint-WorkLabProviderVm {
    <#
    .SYNOPSIS
        Proxmox provider: snapshot a VM. (REAL, idempotent)

    .DESCRIPTION
        Creates a named snapshot of the resolved VM. Idempotent: if a
        snapshot of that name already exists it is returned unchanged.

    .PARAMETER Context
        Property bag with Options (Server/auth/Node).

    .PARAMETER VmName
        WorkLab VM name (lab-<slug>-<role>NN).

    .PARAMETER CheckpointName
        Snapshot name.

    .PARAMETER Description
        Optional snapshot description.

    .PARAMETER IncludeVmState
        Include live RAM/CPU state (for running VMs).

    .EXAMPLE
        Checkpoint-WorkLabProviderVm -Context $c -VmName lab-twoforest-dc01 -CheckpointName pre-patch

    .OUTPUTS
        pscustomobject: Provider, VmName, VmId, Name, Existed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$CheckpointName,
        [Parameter()][string]$Description,
        [Parameter()][switch]$IncludeVmState,
        [Parameter(ValueFromRemainingArguments)]$Rest
    )

    $t = Resolve-WorkLabProxmoxVmTarget -Context $Context -VmName $VmName -RequireOption @('Node')
    if (-not $t.Resolved.Exists) {
        throw "VM '$VmName' not found. Create it first: New-WorkLabProviderVm -Context <ctx> -VmName $VmName."
    }
    $settings = $t.Settings; $session = $t.Session; $id = $t.Identity

    $existing = Get-WorkLabProxmoxSnapshot -Settings $settings -Session $session -VmId $id.VmId -Name $CheckpointName
    if ($existing) {
        Write-Warning "Snapshot '$CheckpointName' already exists on '$VmName'; reconciled (no change)."
        return [pscustomobject]@{ Provider = 'Proxmox'; VmName = $VmName; VmId = $id.VmId; Name = $CheckpointName; Existed = $true }
    }

    if ($PSCmdlet.ShouldProcess("$VmName (VMID $($id.VmId))", "New-PveSnapshot '$CheckpointName'")) {
        $snap = @{
            Node = $settings.Node; VmId = $id.VmId; Name = $CheckpointName
            Wait = $true; Session = $session; Confirm = $false; ErrorAction = 'Stop'
        }
        if ($Description) { $snap['Description'] = $Description }
        if ($IncludeVmState) { $snap['IncludeVmState'] = $true }
        New-PveSnapshot @snap
        return [pscustomobject]@{ Provider = 'Proxmox'; VmName = $VmName; VmId = $id.VmId; Name = $CheckpointName; Existed = $false }
    }
}
