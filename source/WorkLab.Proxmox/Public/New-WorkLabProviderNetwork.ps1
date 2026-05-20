function New-WorkLabProviderNetwork {
    <#
    .SYNOPSIS
        Proxmox provider: create the per-lab SDN VNet. (REAL, idempotent)

    .DESCRIPTION
        Derives a deterministic VNet id + VLAN tag from the lab slug and
        creates an SDN VNet under the configured VLAN zone, then applies the
        SDN config cluster-wide. Idempotent: if the VNet already exists it is
        returned unchanged (reconcile, never duplicate).

    .PARAMETER Context
        LabContext or property bag with Options (Server/auth/Zone/VLAN pool)
        and Slug.

    .EXAMPLE
        New-WorkLabProviderNetwork -Context @{ Slug='twoforest'; Options=$opts }

    .OUTPUTS
        pscustomobject: Name, Tag, Zone, Provider, Existed, Raw.
    #>
    [CmdletBinding(SupportsShouldProcess)]
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
        throw "Proxmox New-WorkLabProviderNetwork requires a Slug in the Context (Context.Slug)."
    }
    $id = Get-WorkLabProxmoxNetworkIdentity -Slug $settings.Slug -PoolStart $settings.VlanPoolStart -PoolEnd $settings.VlanPoolEnd
    $session = Connect-WorkLabProxmox -Settings $settings

    $existing = Get-PveSdnVnet -Vnet $id.Vnet -Session $session -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warning "VNet '$($id.Vnet)' already exists for slug '$($settings.Slug)'; reconciled (no change)."
        return [pscustomobject]@{
            Name     = $id.Vnet
            Tag      = $id.Tag
            Zone     = $settings.Zone
            Provider = 'Proxmox'
            Existed  = $true
            Raw      = $existing
        }
    }

    if ($PSCmdlet.ShouldProcess("$($id.Vnet) (zone $($settings.Zone), VLAN $($id.Tag))", 'New-PveSdnVnet')) {
        New-PveSdnVnet -Vnet $id.Vnet -Zone $settings.Zone -Tag $id.Tag -Alias "worklab/$($settings.Slug)" -Session $session -ErrorAction Stop
        Invoke-PveSdnApply -Session $session -Confirm:$false -ErrorAction Stop
        $created = Get-PveSdnVnet -Vnet $id.Vnet -Session $session -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            Name     = $id.Vnet
            Tag      = $id.Tag
            Zone     = $settings.Zone
            Provider = 'Proxmox'
            Existed  = $false
            Raw      = $created
        }
    }
}
