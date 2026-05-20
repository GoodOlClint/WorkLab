function Restore-Lab {
    <#
    .SYNOPSIS
        Restore every computer in a lab to a snapshot. (Phase 0: validates + warns.)

    .DESCRIPTION
        Phase 0 builds the LabContext. Phase 1 dispatches to the provider's
        Restore-WorkLabProviderVm for each computer.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .PARAMETER CheckpointName
        Snapshot label to restore.

    .EXAMPLE
        Restore-Lab -LabRecipe helloworld -ProviderName Proxmox -CheckpointName pre-patch

    .OUTPUTS
        LabContext
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$LabRecipe,

        [Parameter(Mandatory)]
        [string]$ProviderName,

        [Parameter(Mandatory)]
        [string]$CheckpointName
    )
    process {
        $ctx = New-WorkLabContextFromRecipe -LabRecipe $LabRecipe -ProviderName $ProviderName
        if ($PSCmdlet.ShouldProcess($ctx.Slug, "Restore-Lab '$CheckpointName'")) {
            Write-PSFMessage -Level Warning -Message "Restore-Lab: snapshots are Phase 1; lab '{0}' not restored to '{1}'." -StringValues $ctx.Slug, $CheckpointName
        }
        $ctx
    }
}
