function Remove-LabCheckpoint {
    <#
    .SYNOPSIS
        Delete a lab checkpoint. (Phase 0: validates + warns.)

    .DESCRIPTION
        Phase 0 builds the LabContext. Phase 1 removes snapshots via the
        provider's Remove-WorkLabProviderCheckpoint.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .PARAMETER CheckpointName
        Snapshot label to delete.

    .EXAMPLE
        Remove-LabCheckpoint -LabRecipe helloworld -ProviderName Proxmox -CheckpointName pre-patch

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
        if ($PSCmdlet.ShouldProcess($ctx.Slug, "Remove-LabCheckpoint '$CheckpointName'")) {
            Write-PSFMessage -Level Warning -Message "Remove-LabCheckpoint: snapshots are Phase 1; checkpoint '{0}' not removed for lab '{1}'." -StringValues $CheckpointName, $ctx.Slug
        }
        $ctx
    }
}
