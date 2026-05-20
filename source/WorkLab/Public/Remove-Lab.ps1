function Remove-Lab {
    <#
    .SYNOPSIS
        Tear down a lab's VMs and network. (REAL, idempotent)

    .DESCRIPTION
        Enumerates the lab's VMs (provider list-mode by slug), removes each,
        then removes the per-lab network. Idempotent: missing resources are
        no-ops.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .EXAMPLE
        Remove-Lab -LabRecipe helloworld -ProviderName Proxmox

    .OUTPUTS
        pscustomobject: Slug, Removed (VM names), NetworkRemoved.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

        if (-not $PSCmdlet.ShouldProcess($ctx.Slug, 'Remove-Lab')) { return }

        $vms = @(Invoke-WorkLabProviderCommand -Provider $provider -Verb 'Get' -Noun 'Vm' `
                -Arguments @{ Context = $pctx })

        $removed = foreach ($vm in $vms) {
            Invoke-WorkLabProviderCommand -Provider $provider -Verb 'Remove' -Noun 'Vm' `
                -Arguments @{ Context = $pctx; VmName = $vm.Name } | Out-Null
            $vm.Name
        }

        $net = Invoke-WorkLabProviderCommand -Provider $provider -Verb 'Remove' -Noun 'Network' `
            -Arguments @{ Context = $pctx }

        [pscustomobject]@{
            Slug           = $ctx.Slug
            Removed        = [string[]]$removed
            NetworkRemoved = [bool]($net.Removed)
        }
    }
}
