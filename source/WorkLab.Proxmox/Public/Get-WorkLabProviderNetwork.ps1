function Get-WorkLabProviderNetwork {
    <#
    .SYNOPSIS
        Proxmox provider: get the per-lab SDN VNet. (REAL)

    .DESCRIPTION
        Derives the deterministic VNet id from the lab slug and returns the
        SDN VNet if present, otherwise $null.

    .PARAMETER Context
        LabContext or property bag with Options and Slug.

    .EXAMPLE
        Get-WorkLabProviderNetwork -Context @{ Slug='twoforest'; Options=$opts }

    .OUTPUTS
        pscustomobject (Name, Tag, Zone, Provider, Raw) or $null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object]$Context,

        [Parameter(ValueFromRemainingArguments)]
        $Rest
    )

    $settings = Resolve-WorkLabProxmoxContext -Context $Context
    Assert-WorkLabProxmoxOption -Settings $settings -Required @('Zone')
    if ([string]::IsNullOrWhiteSpace($settings.Slug)) {
        throw "Proxmox Get-WorkLabProviderNetwork requires a Slug in the Context (Context.Slug)."
    }
    $id = Get-WorkLabProxmoxNetworkIdentity -Slug $settings.Slug -PoolStart $settings.VlanPoolStart -PoolEnd $settings.VlanPoolEnd
    $session = Connect-WorkLabProxmox -Settings $settings

    $vnet = Get-PveSdnVnet -Vnet $id.Vnet -Session $session -ErrorAction SilentlyContinue
    if (-not $vnet) {
        Write-Verbose "No VNet '$($id.Vnet)' for slug '$($settings.Slug)'."
        return $null
    }

    [pscustomobject]@{
        Name     = $id.Vnet
        Tag      = $id.Tag
        Zone     = $settings.Zone
        Provider = 'Proxmox'
        Raw      = $vnet
    }
}
