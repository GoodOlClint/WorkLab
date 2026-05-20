function ConvertTo-WorkLabProxmoxVm {
    <#
    .SYNOPSIS
        Normalize a PSProxmoxVE VM object into the WorkLab provider shape.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Vm,
        [Parameter()][string]$Node
    )

    [pscustomobject]@{
        Provider = 'Proxmox'
        Name     = $Vm.Name
        VmId     = $Vm.VmId
        Node     = if ($Vm.Node) { $Vm.Node } else { $Node }
        Status   = $Vm.Status
        Raw      = $Vm
    }
}
