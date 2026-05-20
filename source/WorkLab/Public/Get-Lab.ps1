function Get-Lab {
    <#
    .SYNOPSIS
        Get a provisioned lab's live state. (REAL)

    .DESCRIPTION
        Returns the lab slug, provider, and its current VMs (provider
        list-mode by slug). Empty Computers means nothing is provisioned.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .EXAMPLE
        Get-Lab -LabRecipe helloworld -ProviderName Proxmox

    .OUTPUTS
        pscustomobject: Slug, Provider, Computers.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$LabRecipe,

        [Parameter(Mandatory)]
        [string]$ProviderName
    )
    process {
        $ctx = New-WorkLabContextFromRecipe -LabRecipe $LabRecipe -ProviderName $ProviderName
        $provider = $ctx.Provider
        $pctx = New-WorkLabProviderContext -Provider $provider -Slug $ctx.Slug

        $vms = @(Invoke-WorkLabProviderCommand -Provider $provider -Verb 'Get' -Noun 'Vm' `
                -Arguments @{ Context = $pctx })

        [pscustomobject]@{
            Slug      = $ctx.Slug
            Provider  = $provider.Name
            Computers = [pscustomobject[]]$vms
        }
    }
}
