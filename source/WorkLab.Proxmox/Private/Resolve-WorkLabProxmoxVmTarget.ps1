function Resolve-WorkLabProxmoxVmTarget {
    <#
    .SYNOPSIS
        Connect + resolve a single WorkLab VM target for a VM-scoped op.
    .DESCRIPTION
        Centralizes the settings/assert/connect/identity/resolve sequence so
        every VM-scoped public cmdlet stays thin and consistent. Returns
        Settings, Session, Identity, and the Resolve-WorkLabProxmoxVm result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter()][string[]]$RequireOption = @('Node')
    )

    if ([string]::IsNullOrWhiteSpace($VmName)) {
        throw 'Proxmox VM operations require -VmName (lab-<slug>-<role>NN).'
    }
    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    Assert-WorkLabProxmoxOption -Settings $settings -Required $RequireOption
    $session = Connect-WorkLabProxmox -Settings $settings
    $identity = Get-WorkLabProxmoxVmIdentity -Name $VmName `
        -PoolStart $settings.VmIdPoolStart -PoolEnd $settings.VmIdPoolEnd
    $resolved = Resolve-WorkLabProxmoxVm -Settings $settings -Session $session -Identity $identity

    [pscustomobject]@{
        Settings = $settings
        Session  = $session
        Identity = $identity
        Resolved = $resolved
    }
}
