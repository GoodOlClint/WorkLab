function Resolve-WorkLabProxmoxContext {
    <#
    .SYNOPSIS
        Normalize the inbound $Context into Proxmox connection settings.
    .DESCRIPTION
        Providers stay decoupled from WorkLab core classes: $Context may be a
        LabContext, a hashtable, or any property bag.

        Server + auth are universally required (you must connect for every
        op) and are validated here. Op-specific options (Zone for network,
        Node/DiskStorage for VM, Node/IsoStorage for ISO) are returned as-is
        and validated at point of use via Assert-WorkLabProxmoxOption, so a
        network-only or VM-only caller is not forced to supply unrelated
        options.

        Options: Server, (ApiToken | Credential) [required]; Port,
        SkipCertificateCheck, Zone, Node, IsoStorage, DiskStorage,
        VlanPoolStart (100), VlanPoolEnd (200), VmIdPoolStart (9000),
        VmIdPoolEnd (9999) [optional].
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][object]$Context
    )

    $options = Get-WorkLabProxmoxContextValue -InputObject $Context -Name 'Options'
    if ($null -eq $options) {
        throw "Proxmox provider Context has no 'Options'. Register the provider with connection settings: Register-WorkLabProvider -Name Proxmox -Options @{ Server='pve.lan'; ApiToken='user@pam!id=uuid'; Node='pve1' }"
    }

    $server = Get-WorkLabProxmoxContextValue -InputObject $options -Name 'Server'
    if ([string]::IsNullOrWhiteSpace($server)) {
        throw "Proxmox provider Options.Server is required (e.g. 'pve.lan')."
    }

    @{
        Server               = $server
        Port                 = (Get-WorkLabProxmoxContextValue -InputObject $options -Name 'Port')
        ApiToken             = (Get-WorkLabProxmoxContextValue -InputObject $options -Name 'ApiToken')
        Credential           = (Get-WorkLabProxmoxContextValue -InputObject $options -Name 'Credential')
        SkipCertificateCheck = [bool](Get-WorkLabProxmoxContextValue -InputObject $options -Name 'SkipCertificateCheck')
        Zone                 = (Get-WorkLabProxmoxContextValue -InputObject $options -Name 'Zone')
        Node                 = (Get-WorkLabProxmoxContextValue -InputObject $options -Name 'Node')
        IsoStorage           = (Get-WorkLabProxmoxContextValue -InputObject $options -Name 'IsoStorage')
        DiskStorage          = (Get-WorkLabProxmoxContextValue -InputObject $options -Name 'DiskStorage')
        VlanPoolStart        = [int]((Get-WorkLabProxmoxContextValue -InputObject $options -Name 'VlanPoolStart') ?? 100)
        VlanPoolEnd          = [int]((Get-WorkLabProxmoxContextValue -InputObject $options -Name 'VlanPoolEnd') ?? 200)
        VmIdPoolStart        = [int]((Get-WorkLabProxmoxContextValue -InputObject $options -Name 'VmIdPoolStart') ?? 9000)
        VmIdPoolEnd          = [int]((Get-WorkLabProxmoxContextValue -InputObject $options -Name 'VmIdPoolEnd') ?? 9999)
        Slug                 = (Get-WorkLabProxmoxContextValue -InputObject $Context -Name 'Slug')
    }
}
