function Remove-WorkLabProviderNetwork {
    <#
    .SYNOPSIS
        Proxmox provider: remove the per-lab SDN VNet. (REAL, idempotent)

    .DESCRIPTION
        Derives the deterministic VNet id from the lab slug, removes the SDN
        VNet if present, and applies the SDN config cluster-wide. Idempotent:
        a missing VNet is a no-op.

    .PARAMETER Context
        LabContext or property bag with Options and Slug.

    .EXAMPLE
        Remove-WorkLabProviderNetwork -Context @{ Slug='twoforest'; Options=$opts }

    .OUTPUTS
        pscustomobject: Name, Removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
        throw "Proxmox Remove-WorkLabProviderNetwork requires a Slug in the Context (Context.Slug)."
    }
    $id = Get-WorkLabProxmoxNetworkIdentity -Slug $settings.Slug -PoolStart $settings.VlanPoolStart -PoolEnd $settings.VlanPoolEnd
    $session = Connect-WorkLabProxmox -Settings $settings

    $existing = Get-PveSdnVnet -Vnet $id.Vnet -Session $session -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Verbose "VNet '$($id.Vnet)' not present for slug '$($settings.Slug)'; nothing to remove."
        return [pscustomobject]@{ Name = $id.Vnet; Removed = $false }
    }

    if ($PSCmdlet.ShouldProcess($id.Vnet, 'Remove-PveSdnVnet')) {
        Remove-PveSdnVnet -Vnet $id.Vnet -Session $session -Confirm:$false -ErrorAction Stop
        Invoke-PveSdnApply -Session $session -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ Name = $id.Vnet; Removed = $true }
    }
}
