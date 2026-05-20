function Reset-Lab {
    <#
    .SYNOPSIS
        Reset a lab to its initial provisioned state. (Phase 0: validates + warns.)

    .DESCRIPTION
        Phase 0 validates inputs and builds the LabContext. Phase 1 will
        restore each computer to its post-Initialize baseline.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .EXAMPLE
        Reset-Lab -LabRecipe helloworld -ProviderName Proxmox

    .OUTPUTS
        LabContext
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$LabRecipe,

        [Parameter(Mandatory)]
        [string]$ProviderName
    )
    process {
        $ctx = New-WorkLabContextFromRecipe -LabRecipe $LabRecipe -ProviderName $ProviderName
        if ($PSCmdlet.ShouldProcess($ctx.Slug, 'Reset-Lab')) {
            Write-PSFMessage -Level Warning -Message "Reset-Lab: orchestration is Phase 1; lab '{0}' unchanged." -StringValues $ctx.Slug
        }
        $ctx
    }
}
