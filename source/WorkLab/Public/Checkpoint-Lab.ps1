function Checkpoint-Lab {
    <#
    .SYNOPSIS
        Snapshot every computer in a lab. (Phase 0: validates + warns.)

    .DESCRIPTION
        Phase 0 builds the LabContext. Phase 1 dispatches to the provider's
        Checkpoint-WorkLabProviderVm for each computer.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .PARAMETER CheckpointName
        Snapshot label.

    .EXAMPLE
        Checkpoint-Lab -LabRecipe helloworld -ProviderName Proxmox -CheckpointName pre-patch

    .OUTPUTS
        LabContext
    #>
    [CmdletBinding(SupportsShouldProcess)]
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
        if ($PSCmdlet.ShouldProcess($ctx.Slug, "Checkpoint-Lab '$CheckpointName'")) {
            Write-PSFMessage -Level Warning -Message "Checkpoint-Lab: snapshots are Phase 1; no checkpoint '{0}' taken for lab '{1}'." -StringValues $CheckpointName, $ctx.Slug
        }
        $ctx
    }
}
