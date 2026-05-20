function Initialize-Lab {
    <#
    .SYNOPSIS
        Create/reconcile a lab from a lab recipe. (REAL, idempotent)

    .DESCRIPTION
        Orchestrates Phase 1 provider ops + the lazy hybrid template cache:
        ensure the per-lab network, ensure a sysprepped template for each
        component's image, then clone one VM per computed computer and start
        it. Idempotent: re-running reconciles (provider ops + template cache
        are idempotent), never duplicates.

        ADDS DSC promotion is intentionally deferred to Phase 2.5 (guest
        reachability on the isolated per-lab VNet is unresolved); it is logged
        as a deferred step, not attempted.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .EXAMPLE
        Initialize-Lab -LabRecipe helloworld -ProviderName Proxmox

    .OUTPUTS
        pscustomobject lab summary (Slug, Provider, Computers, DscDeferred).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$LabRecipe,

        [Parameter(Mandatory)]
        [string]$ProviderName
    )
    process {
        $plan = Resolve-WorkLabComputerPlan -LabRecipe $LabRecipe -ProviderName $ProviderName
        $ctx = $plan.Context
        $provider = $ctx.Provider
        $pctx = New-WorkLabProviderContext -Provider $provider -Slug $ctx.Slug

        if (-not $PSCmdlet.ShouldProcess($ctx.Slug, 'Initialize-Lab')) { return }

        Invoke-WorkLabProviderCommand -Provider $provider -Verb 'New' -Noun 'Network' `
            -Arguments @{ Context = $pctx } | Out-Null

        $templateByImage = @{}
        foreach ($image in ($plan.Computers.Image | Sort-Object -Unique)) {
            $tpl = New-WorkLabImageTemplate -Provider $provider -ImageName $image
            $templateByImage[$image] = $tpl.TemplateName
        }

        $result = foreach ($c in $plan.Computers) {
            $tplName = $templateByImage[$c.Image]
            Invoke-WorkLabProviderCommand -Provider $provider -Verb 'Copy' -Noun 'Vm' -Arguments @{
                Context = $pctx; TemplateName = $tplName; VmName = $c.VmName; Start = $true
            } | Out-Null
            Write-PSFMessage -Level Warning -Message "ADDS/role DSC for '{0}' deferred to Phase 2.5 (guest reachability TBD)." -StringValues $c.ComputerName
            [pscustomobject]@{
                Name = $c.VmName; ComputerName = $c.ComputerName; Role = $c.Role
                Index = $c.Index; Image = $c.Image; Template = $tplName
            }
        }

        [pscustomobject]@{
            Slug        = $ctx.Slug
            Provider    = $provider.Name
            Computers   = [pscustomobject[]]$result
            DscDeferred = $true
        }
    }
}
