function Get-LabCheckpoint {
    <#
    .SYNOPSIS
        List checkpoints for a lab. (Phase 0: validates + warns.)

    .DESCRIPTION
        Phase 0 builds the LabContext. Phase 1 enumerates snapshots via the
        provider's Get-WorkLabProviderCheckpoint.

    .PARAMETER LabRecipe
        Name of a *.lab.psd1 recipe.

    .PARAMETER ProviderName
        Registered provider to target.

    .EXAMPLE
        Get-LabCheckpoint -LabRecipe helloworld -ProviderName Proxmox

    .OUTPUTS
        LabContext
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$LabRecipe,

        [Parameter(Mandatory)]
        [string]$ProviderName
    )
    process {
        $ctx = New-WorkLabContextFromRecipe -LabRecipe $LabRecipe -ProviderName $ProviderName
        Write-PSFMessage -Level Warning -Message "Get-LabCheckpoint: snapshots are Phase 1; none for lab '{0}'." -StringValues $ctx.Slug
        $ctx
    }
}
